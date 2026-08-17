import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../ad_detail_screen.dart';

/// Shown right after an ad is published - the "Success, your ad is listed"
/// celebration, mirroring the website (two-people illustration + share row +
/// View ad). Pop it (or "Place another") to return to a fresh Place-an-ad form.
class AdLiveScreen extends StatelessWidget {
  final int? adId;
  final String title;
  final ApiService api;
  final AuthService? auth;

  const AdLiveScreen({
    super.key,
    required this.adId,
    required this.title,
    required this.api,
    this.auth,
  });

  String get _adUrl =>
      adId != null ? 'https://listit.im/ads/$adId' : 'https://listit.im';

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.ink),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/adlisted.png',
                  height: 220, fit: BoxFit.contain),
              const SizedBox(height: 14),
              _factPill(),
              const SizedBox(height: 18),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 26),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text('Your ad is live!',
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title.trim().isEmpty
                    ? 'Nice one — your listing is now on List it for buyers across the Isle of Man to find. It may take a few minutes to appear.'
                    : '"${title.trim()}" is now on List it for buyers across the Isle of Man to find. It may take a few minutes to appear.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.slate, fontSize: 14.5, height: 1.45),
              ),
              const SizedBox(height: 24),
              const Text('Share your ad',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _shareChip(Icons.facebook, const Color(0xFF1877F2), () {
                    _open(
                        'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_adUrl)}');
                  }),
                  _shareChip(Icons.chat_rounded, const Color(0xFF25D366), () {
                    _open('https://wa.me/?text=${Uri.encodeComponent(_adUrl)}');
                  }),
                  _shareChip(Icons.share_rounded, AppColors.primary, () {
                    Share.share(
                        title.trim().isEmpty
                            ? _adUrl
                            : 'Check out "${title.trim()}" on List it\n$_adUrl',
                        subject: 'Check out my ad on List it');
                  }),
                  _shareChip(Icons.link_rounded, AppColors.slate, () async {
                    await Clipboard.setData(ClipboardData(text: _adUrl));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    }
                  }),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: adId == null
                      ? null
                      : () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AdDetailScreen(
                                adId: adId!, api: api, auth: auth),
                          ));
                        },
                  child: const Text('View ad',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  child: const Text('Place another',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A light-hearted "fact of the day" from Larry, the List it pup. Rotates
  /// once a day (stable within a day, changes tomorrow) so every visit feels a
  /// little different. A few selling tips are mixed in with the fun facts.
  static const List<String> _dogFacts = [
    'Dachshunds were bred in Germany to hunt badgers — their name literally means "badger dog".',
    'A dog\'s sense of smell can be up to 100,000 times sharper than ours.',
    'Dachshunds are the smallest breed ever used for hunting.',
    'Dogs can learn more than 1,000 words and gestures.',
    'The Isle of Man is home to Tynwald, the world\'s oldest continuous parliament.',
    'Puppies are born deaf — their hearing switches on after a few weeks.',
    'A dog\'s nose print is as unique as a human fingerprint.',
    'Manx cats from the Isle of Man are famously born without tails.',
    'A wagging tail doesn\'t always mean happy — it depends which way it wags!',
    'Dachshunds come in three coats: smooth, wire-haired and long-haired.',
    'Dogs dream just like we do — watch those little twitching paws.',
    'A greyhound could out-run a cheetah over a long distance.',
    'The sausage dog "Waldi" was the very first official Olympic mascot, in 1972.',
    'Dogs curl up to sleep to protect their vital organs and stay warm.',
    'Three dogs survived the sinking of the Titanic.',
    'A dog\'s whiskers help it "see" in the dark.',
    'Dogs sweat through their paw pads, not their skin.',
    'The Isle of Man has its own currency — the Manx pound.',
    'Bright, daylight photos can sell an ad up to twice as fast.',
    'Ads with a clear price get noticeably more replies than "POA".',
    'A short, friendly title sells faster than one in ALL CAPS.',
    'Adding a few extra photos is one of the best ways to get more enquiries.',
  ];

  String get _factOfTheDay {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return _dogFacts[dayOfYear % _dogFacts.length];
  }

  Widget _factPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          const Text('🐾  Larry\'s fact of the day',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.2)),
          const SizedBox(height: 5),
          Text(_factOfTheDay,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13.5, color: AppColors.ink, height: 1.4)),
        ],
      ),
    );
  }

  Widget _shareChip(IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}
