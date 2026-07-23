import 'package:flutter/material.dart';

import '../models/ad.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/network_photo.dart';
import 'ad_detail_screen.dart';

/// The user's saved ads - everything they hearted from the swipe deck or a
/// listing. Pulls from GET /save-ad (auth) and opens each into full detail.
class SavedAdsScreen extends StatefulWidget {
  final ApiService api;
  final int userId;
  const SavedAdsScreen({super.key, required this.api, required this.userId});

  @override
  State<SavedAdsScreen> createState() => _SavedAdsScreenState();
}

class _SavedAdsScreenState extends State<SavedAdsScreen> {
  late Future<List<Ad>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listSavedAds(userId: widget.userId);
  }

  void _reload() =>
      setState(() => _future = widget.api.listSavedAds(userId: widget.userId));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Saved ads')),
      body: FutureBuilder<List<Ad>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError) {
            return _message(
              'Could not load your saved ads.',
              action: TextButton(onPressed: _reload, child: const Text('Retry')),
            );
          }
          final ads = snap.data ?? const [];
          if (ads.isEmpty) {
            return _message(
              'No saved ads yet.\nTap the heart on any listing to keep it here.',
            );
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: ads.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _SavedCard(
                ad: ads[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdDetailScreen(
                        adId: ads[i].id, api: widget.api, preview: ads[i]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _message(String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmark_border_rounded,
                size: 48, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 12), action],
          ],
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final Ad ad;
  final VoidCallback onTap;
  const _SavedCard({required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NetworkPhoto(url: ad.coverImage, width: 96, height: 96),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ad.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Format.price(ad),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary),
                    ),
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
