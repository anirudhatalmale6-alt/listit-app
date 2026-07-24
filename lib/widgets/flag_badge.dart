import 'package:flutter/material.dart';

/// A small rounded country flag rendered from a bundled PNG (assets/flags/).
/// Bundled raster images render identically on Android, iOS and web — unlike
/// emoji flags (🇮🇲 / 🇬🇧), which don't show on most Android devices, which is
/// exactly where this app ships.
class FlagBadge extends StatelessWidget {
  final String iso;
  final double width;
  final double height;
  const FlagBadge({super.key, required this.iso, this.width = 26, this.height = 18});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.asset(
        'assets/flags/${iso.toLowerCase()}.png',
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => SizedBox(
          width: width,
          height: height,
          child: const ColoredBox(color: Color(0xFFE6E8EB)),
        ),
      ),
    );
  }
}
