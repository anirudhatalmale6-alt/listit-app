import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/recently_viewed.dart';
import '../theme.dart';
import '../widgets/network_photo.dart';
import 'ad_detail_screen.dart';

/// The ads the user has looked at, most recent first (DoneDeal's "Browsing
/// history"). Stored on the device, so it's here whether signed in or not.
class RecentlyViewedScreen extends StatefulWidget {
  final ApiService api;
  const RecentlyViewedScreen({super.key, required this.api});

  @override
  State<RecentlyViewedScreen> createState() => _RecentlyViewedScreenState();
}

class _RecentlyViewedScreenState extends State<RecentlyViewedScreen> {
  late Future<List<ViewedAd>> _future;

  static final NumberFormat _gbp = NumberFormat.currency(
      locale: 'en_GB', symbol: '£', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _future = RecentlyViewed.load();
  }

  void _reload() => setState(() => _future = RecentlyViewed.load());

  Future<void> _clear() async {
    await RecentlyViewed.clear();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Recently Viewed'),
        actions: [
          FutureBuilder<List<ViewedAd>>(
            future: _future,
            builder: (context, snap) {
              if ((snap.data ?? const []).isEmpty) return const SizedBox.shrink();
              return TextButton(
                  onPressed: _clear, child: const Text('Clear'));
            },
          ),
        ],
      ),
      body: FutureBuilder<List<ViewedAd>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final ads = snap.data ?? const [];
          if (ads.isEmpty) {
            return const _Message(
                'Nothing here yet.\nAds you open will show up here so you can get back to them.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: ads.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ViewedCard(
              ad: ads[i],
              price: ads[i].isFree ? 'Free' : _gbp.format(ads[i].price),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                    builder: (_) =>
                        AdDetailScreen(adId: ads[i].id, api: widget.api),
                  ))
                  .then((_) => _reload()),
            ),
          );
        },
      ),
    );
  }
}

class _ViewedCard extends StatelessWidget {
  final ViewedAd ad;
  final String price;
  final VoidCallback onTap;
  const _ViewedCard(
      {required this.ad, required this.price, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NetworkPhoto(url: ad.image, width: 96, height: 96),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(ad.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                    const SizedBox(height: 6),
                    Text(price,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                    if (ad.location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: AppColors.muted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(ad.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.slate)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_rounded, size: 48, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
