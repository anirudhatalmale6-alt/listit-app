import 'package:flutter/material.dart';

import '../models/ad.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/network_photo.dart';

/// Full listing view. Opened from a tap on a swipe card. Loads the richer
/// `/ads/:id` payload while showing the data we already have from the deck as
/// an instant preview, so the screen never flashes empty.
class AdDetailScreen extends StatefulWidget {
  final int adId;
  final ApiService api;
  final Ad? preview;

  const AdDetailScreen({
    super.key,
    required this.adId,
    required this.api,
    this.preview,
  });

  @override
  State<AdDetailScreen> createState() => _AdDetailScreenState();
}

class _AdDetailScreenState extends State<AdDetailScreen> {
  final PageController _gallery = PageController();
  int _photoIndex = 0;

  Ad? _ad;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ad = widget.preview;
    _load();
  }

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final full = await widget.api.fetchAd(widget.adId);
      if (!mounted) return;
      setState(() {
        _ad = full;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = widget.preview == null ? e.toString() : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.slate),
                  ),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
      );
    }
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _galleryAppBar(ad),
          SliverToBoxAdapter(child: _content(ad)),
        ],
      ),
      bottomNavigationBar: _contactBar(ad),
    );
  }

  Widget _galleryAppBar(Ad ad) {
    final photos = ad.images;
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isEmpty)
              const NetworkPhoto(url: null)
            else
              PageView.builder(
                controller: _gallery,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _photoIndex = i),
                itemBuilder: (_, i) => NetworkPhoto(url: photos[i]),
              ),
            if (photos.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    photos.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _photoIndex ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _photoIndex
                            ? Colors.white
                            : Colors.white54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(Ad ad) {
    final old = Format.oldPrice(ad);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Format.price(ad),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (old != null) ...[
                const SizedBox(width: 10),
                Text(
                  old,
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.muted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ad.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 18, color: AppColors.slate),
              const SizedBox(width: 4),
              Text(
                ad.location.isEmpty ? 'Isle of Man' : ad.location,
                style: const TextStyle(color: AppColors.slate, fontSize: 15),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.schedule, size: 16, color: AppColors.slate),
              const SizedBox(width: 4),
              Text(
                Format.timeAgo(ad.createdAt),
                style: const TextStyle(color: AppColors.slate, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sellerRow(ad),
          const Divider(height: 40),
          const Text(
            'Description',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ad.description.trim().isEmpty
                ? 'No description provided.'
                : ad.description.trim(),
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _stat(Icons.visibility_outlined, '${ad.viewCount} views'),
              const SizedBox(width: 20),
              _stat(Icons.favorite_border, '${ad.likeCount} likes'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sellerRow(Ad ad) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              _initials(ad.displayName),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.displayName.isEmpty ? 'Private seller' : ad.displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  ad.isDealer ? 'Business seller' : 'Private seller',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.slate,
                  ),
                ),
              ],
            ),
          ),
          if (ad.isDealer)
            const Icon(Icons.verified, color: AppColors.primary, size: 22),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.slate),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: AppColors.slate, fontSize: 14)),
      ],
    );
  }

  Widget _contactBar(Ad ad) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            _outlineAction(
              icon: Icons.bookmark_border_rounded,
              label: 'Save',
              onTap: () => _notImplemented('Saving'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _notImplemented('Messaging the seller'),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                label: const Text('Message seller'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlineAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: AppColors.primary),
      label: Text(label, style: const TextStyle(color: AppColors.primary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _notImplemented(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$what arrives in the next phase (accounts & chat).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
