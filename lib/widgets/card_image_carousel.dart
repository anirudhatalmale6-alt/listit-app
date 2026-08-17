import 'package:flutter/material.dart';

import '../theme.dart';

import 'network_photo.dart';

/// A swipeable image strip for a listing card, so buyers can flick through the
/// photos without opening the ad (like DoneDeal). Shows dots and an "n / total"
/// counter over the image; a single tap anywhere falls through to [onTap] to
/// open the ad. Falls back to a single image when there's only one.
class CardImageCarousel extends StatefulWidget {
  final List<String> images;
  final double aspectRatio;

  const CardImageCarousel({
    super.key,
    required this.images,
    this.aspectRatio = 16 / 10,
  });

  @override
  State<CardImageCarousel> createState() => _CardImageCarouselState();
}

class _CardImageCarouselState extends State<CardImageCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imgs = widget.images;
    if (imgs.length <= 1) {
      // Taps fall through to the card's own InkWell (opens the ad).
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: NetworkPhoto(
          url: imgs.isNotEmpty ? imgs.first : null,
          fit: BoxFit.cover,
        ),
      );
    }
    // Cap the number of swipeable photos on the card so a 30-image ad doesn't
    // build 30 network images in a list; the rest are on the detail page.
    final count = imgs.length > 10 ? 10 : imgs.length;
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: count,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => NetworkPhoto(url: imgs[i], fit: BoxFit.cover),
          ),
          // "n / total" counter, top-right.
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined,
                      size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('${_index + 1} / ${imgs.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          // Dots along the bottom.
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: i == _index ? 8 : 6,
                    height: i == _index ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 2),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
