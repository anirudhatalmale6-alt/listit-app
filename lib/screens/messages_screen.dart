import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/network_photo.dart';
import 'auth/auth_screen.dart';
import 'chat_screen.dart';

/// The Messages tab - the buyer/seller's inbox. Lists every thread newest
/// first with an unread badge, and refreshes itself on a light timer so new
/// replies surface without a manual pull. Gated behind sign-in.
class MessagesScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const MessagesScreen({super.key, required this.api, required this.auth});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Conversation> _items = const [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  int get _me => widget.auth.user?.id ?? 0;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
    if (widget.auth.isLoggedIn) {
      _load();
      _startPoll();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    _poll?.cancel();
    super.dispose();
  }

  void _onAuth() {
    if (!mounted) return;
    if (widget.auth.isLoggedIn) {
      setState(() => _loading = true);
      _load();
      _startPoll();
    } else {
      _poll?.cancel();
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && widget.auth.isLoggedIn) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!widget.auth.isLoggedIn) return;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final list = await widget.api.listConversations(userId: _me);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = e.toString();
      });
    }
  }

  Future<void> _openChat(Conversation c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        api: widget.api,
        auth: widget.auth,
        conversationId: c.id,
        otherName: c.other(_me).displayName,
      ),
    ));
    _load(silent: true); // unread counts may have changed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (!widget.auth.isLoggedIn) return _signedOut();
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _empty(
        icon: Icons.wifi_off_rounded,
        title: 'Couldn’t load messages',
        message: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_items.isEmpty) {
      return _empty(
        icon: Icons.forum_outlined,
        title: 'No messages yet',
        message:
            'When you message a seller or someone enquires about your ad, the chat shows up here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 78, color: AppColors.line),
        itemBuilder: (_, i) => _tile(_items[i]),
      ),
    );
  }

  Widget _tile(Conversation c) {
    final other = c.other(_me);
    final unread = c.unreadFor(_me);
    final hasUnread = unread > 0;
    return InkWell(
      onTap: () => _openChat(c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(other),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          other.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Format.timeAgo(c.lastMessageAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: hasUnread ? AppColors.primary : AppColors.muted,
                          fontWeight:
                              hasUnread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (c.adTitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      c.adTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.slate,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.lastMessageText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color:
                                hasUnread ? AppColors.ink : AppColors.slate,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.rectangle,
                            borderRadius:
                                BorderRadius.all(Radius.circular(11)),
                          ),
                          constraints: const BoxConstraints(minWidth: 22),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(ConvParty p) {
    if (p.avatar != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: SizedBox(
          width: 50,
          height: 50,
          child: NetworkPhoto(url: p.avatar),
        ),
      );
    }
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        p.initials,
        style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 17),
      ),
    );
  }

  Widget _signedOut() {
    return _empty(
      icon: Icons.lock_outline_rounded,
      title: 'Sign in to see your messages',
      message:
          'Your chats with buyers and sellers - and any offers - live here once you’re signed in.',
      action: FilledButton(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AuthScreen(auth: widget.auth),
          ));
        },
        child: const Text('Sign in'),
      ),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, height: 1.35)),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
