import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ad.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/network_photo.dart';
import 'ad_detail_screen.dart';

/// One chat thread. Opens three ways:
///  - from the Messages tab with a known [conversationId];
///  - from an ad's "Message" enquiry with [ad] + [sellerId] (compose mode -
///    the thread is created on the first send);
///  - straight after a "Make an offer" with the [conversationId] the offer
///    call returned.
/// Polls the thread every few seconds so replies land without a manual pull.
class ChatScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  final int? conversationId;
  final Ad? ad;
  final int? sellerId;
  final String? otherName;

  const ChatScreen({
    super.key,
    required this.api,
    required this.auth,
    this.conversationId,
    this.ad,
    this.sellerId,
    this.otherName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  int? _convId;
  Ad? _ad;
  String _otherName = '';
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  Timer? _poll;
  final _scroll = ScrollController();
  final _input = TextEditingController();

  int get _me => widget.auth.user?.id ?? 0;

  @override
  void initState() {
    super.initState();
    _convId = widget.conversationId;
    _ad = widget.ad;
    _otherName = widget.otherName ?? '';
    _bootstrap();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Compose mode: see if a thread with this seller already exists so we
    // continue it rather than opening a second one.
    if (_convId == null && _ad != null && widget.sellerId != null) {
      try {
        final existing = await widget.api.findConversation(
          userId: _me,
          adId: _ad!.id,
          sellerId: widget.sellerId!,
        );
        if (existing != null) {
          _convId = existing.id;
          _otherName = existing.other(_me).displayName;
        }
      } catch (_) {/* fall through to a fresh compose */}
    }
    if (_convId != null) {
      await _load();
      _startPoll();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _convId != null) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (_convId == null) return;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final thread = await widget.api
          .listMessages(conversationId: _convId!, userId: _me);
      if (!mounted) return;
      final other = (thread.buyer?.id == _me)
          ? thread.seller
          : (thread.seller?.id == _me ? thread.buyer : thread.seller);
      setState(() {
        _messages = thread.messages;
        if (thread.ad != null) _ad = thread.ad;
        if (other != null && other.displayName.isNotEmpty) {
          _otherName = other.displayName;
        }
        _loading = false;
        _error = null;
      });
      _jumpToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_messages.isEmpty) _error = e.toString();
      });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_convId == null) {
        final id = await widget.api.startConversation(
          adId: _ad!.id,
          buyerId: _me,
          sellerId: widget.sellerId!,
          text: text,
        );
        _input.clear();
        if (id > 0) {
          _convId = id;
          await _load();
          _startPoll();
        }
      } else {
        await widget.api.sendChatMessage(
          conversationId: _convId!,
          senderId: _me,
          text: text,
        );
        _input.clear();
        await _load();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _makeOffer() async {
    if (_ad == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final amount = await showMakeOfferSheet(context, _ad!);
    if (amount == null || !mounted) return;
    try {
      final id = await widget.api.makeOffer(adId: _ad!.id, amount: amount);
      if (id > 0) {
        _convId = id;
        await _load();
        _startPoll();
      }
      messenger.showSnackBar(const SnackBar(
        content: Text('Offer sent to the seller.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  bool get _canOffer =>
      _ad != null && _ad!.allowsOffers && _ad!.userId != _me && _me != 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          _otherName.isEmpty ? 'Message' : _otherName,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_canOffer)
            TextButton.icon(
              onPressed: _makeOffer,
              icon: const Icon(Icons.local_offer_rounded, size: 18),
              label: const Text('Offer'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_ad != null) _adBanner(_ad!),
          Expanded(child: _body()),
          _composer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.slate)),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                _otherName.isEmpty
                    ? 'Send the first message'
                    : 'Say hello to $_otherName',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ask a question, arrange a viewing, or make an offer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.slate, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]),
    );
  }

  Widget _adBanner(Ad ad) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdDetailScreen(
            adId: ad.id,
            api: widget.api,
            preview: ad,
            auth: widget.auth,
          ),
        )),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: NetworkPhoto(url: ad.coverImage),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(Format.price(ad),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    if (m.isOffer) return _offerLine(m);
    final mine = m.senderId == _me;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(m.text,
                style: TextStyle(
                    color: mine ? Colors.white : AppColors.ink,
                    fontSize: 15,
                    height: 1.3)),
            const SizedBox(height: 3),
            Text(Format.timeAgo(m.sentAt),
                style: TextStyle(
                    fontSize: 10.5,
                    color: mine ? Colors.white70 : AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _offerLine(ChatMessage m) {
    final accepted = m.isOfferAccepted;
    final declined = m.isOfferDeclined;
    final color = accepted
        ? AppColors.success
        : (declined ? AppColors.danger : AppColors.primary);
    final icon = accepted
        ? Icons.check_circle_rounded
        : (declined ? Icons.cancel_rounded : Icons.local_offer_rounded);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(m.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    if (_me == 0) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Write a message…',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending ? null : _send,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared "Make an offer" bottom sheet. Returns the entered amount (pounds) or
/// null if the buyer backs out. Validates against the asking price locally so
/// the buyer gets instant feedback before the request goes out.
Future<double?> showMakeOfferSheet(BuildContext context, Ad ad) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => _OfferSheet(ad: ad),
  );
}

class _OfferSheet extends StatefulWidget {
  final Ad ad;
  const _OfferSheet({required this.ad});
  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _ctrl.text.trim().replaceAll(RegExp(r'[^0-9.]'), '');
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (widget.ad.price > 0 && value >= widget.ad.price) {
      setState(() => _error = 'Offer must be below the asking price');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final asking = Format.price(widget.ad);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Make an offer',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('Asking $asking',
                  style: const TextStyle(color: AppColors.slate)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              prefixText: '£ ',
              prefixStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink),
              hintText: '0',
              errorText: _error,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          const Text(
            'The seller gets your offer in chat and can accept or decline.',
            style: TextStyle(color: AppColors.slate, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control)),
              ),
              child: const Text('Send offer',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
