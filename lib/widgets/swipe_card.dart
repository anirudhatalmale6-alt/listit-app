import 'package:flutter/material.dart';

import '../models/ad.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'network_photo.dart';

/// The full-bleed listing card in the swipe deck. Shows the cover photo with a
/// dark gradient foot so the title, price and location stay legible over any
/// image. [overlay] drives the LIKE / NOPE / SAVE stamp as the user drags.
class SwipeCard extends StatelessWidget {
  final Ad ad;
  final SwipeStamp overlay;
  final double overlayOpacity;

  const SwipeCard({
    super.key,
    required this.ad,
    this.overlay = SwipeStamp.none,
    this.overlayOpacity = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        color: AppColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkPhoto(url: ad.coverImage),
            // Legibility gradient.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC000000),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            _topBadges(),
            _info(),
            _stamp(),
          ],
        ),
      ),
    );
  }

  Widget _topBadges() {
    final badges = <Widget>[];
    if (ad.isDealer) {
      badges.add(_pill('Dealer', AppColors.primary));
    }
    if (ad.underOffer) {
      badges.add(_pill('Under offer', AppColors.save));
    }
    if (ad.hasDiscount) {
      badges.add(_pill('Reduced', AppColors.danger));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 16,
      left: 16,
      child: Wrap(
        spacing: 8,
        children: badges,
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _info() {
    final old = Format.oldPrice(ad);
    return Positioned(
      left: 20,
      right: 20,
      bottom: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Format.price(ad),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (old != null) ...[
                const SizedBox(width: 10),
                Text(
                  old,
                  style: const TextStyle(
                    color: Color(0xFFD0D5DD),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ad.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 16, color: Color(0xFFD0D5DD)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  ad.location.isEmpty ? 'Isle of Man' : ad.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD0D5DD),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Format.timeAgo(ad.createdAt),
                style: const TextStyle(
                  color: Color(0xFFB6BEC9),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stamp() {
    if (overlay == SwipeStamp.none || overlayOpacity <= 0) {
      return const SizedBox.shrink();
    }
    final spec = switch (overlay) {
      SwipeStamp.like => (_StampSpec('INTERESTED', AppColors.success, Alignment.topLeft, -0.35)),
      SwipeStamp.nope => (_StampSpec('PASS', AppColors.danger, Alignment.topRight, 0.35)),
      SwipeStamp.save => (_StampSpec('SAVED', AppColors.save, Alignment.topCenter, 0)),
      SwipeStamp.none => (_StampSpec('', Colors.transparent, Alignment.center, 0)),
    };
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Align(
          alignment: spec.align,
          child: Opacity(
            opacity: overlayOpacity.clamp(0, 1),
            child: Transform.rotate(
              angle: spec.angle,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: spec.color, width: 4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  spec.label,
                  style: TextStyle(
                    color: spec.color,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum SwipeStamp { none, like, nope, save }

class _StampSpec {
  final String label;
  final Color color;
  final Alignment align;
  final double angle;
  const _StampSpec(this.label, this.color, this.align, this.angle);
}
