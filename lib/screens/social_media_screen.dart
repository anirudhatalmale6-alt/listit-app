import 'package:flutter/material.dart';

import '../services/site_settings.dart';
import '../theme.dart';
import 'settings_screens.dart';

/// "Social media" - the same links as the website footer (Facebook, X,
/// Instagram, YouTube), pulled live from the site's own settings so
/// the app always points wherever the website does. Tapping opens the profile
/// in the browser / native app.
class SocialMediaScreen extends StatelessWidget {
  const SocialMediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Social media')),
      body: ValueListenableBuilder<Map<String, String>>(
        valueListenable: SiteSettings.values,
        builder: (context, _, _) {
          final platforms = <_Social>[
            _Social('Facebook', SiteSettings.facebook, const Color(0xFF1877F2),
                _FacebookMark()),
            _Social('X', SiteSettings.twitter, const Color(0xFF000000),
                const _TextMark('𝕏')),
            _Social(
                'Instagram', SiteSettings.instagram, const Color(0xFFE1306C),
                const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 20)),
            _Social('YouTube', SiteSettings.youtube, const Color(0xFFFF0000),
                const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 24)),
          ].where((p) => p.url != null && p.url!.isNotEmpty).toList();

          if (platforms.isEmpty) {
            return const _Empty();
          }

          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Follow Listit and keep up with the latest listings and news.',
                  style: TextStyle(
                      color: AppColors.slate, fontSize: 13.5, height: 1.4),
                ),
              ),
              const SizedBox(height: 6),
              for (final p in platforms) _row(p),
            ],
          );
        },
      ),
    );
  }

  Widget _row(_Social p) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: p.mark,
        ),
        title: Text(p.name,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
        subtitle: Text(_pretty(p.url!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
        trailing: const Icon(Icons.open_in_new_rounded,
            size: 18, color: AppColors.muted),
        onTap: () => ListitLinks.open(p.url!),
      ),
    );
  }

  /// A friendly one-liner under each name: the host, minus the "www." noise.
  static String _pretty(String url) {
    var host = url;
    final scheme = host.indexOf('://');
    if (scheme != -1) host = host.substring(scheme + 3);
    final slash = host.indexOf('/');
    if (slash != -1) host = host.substring(0, slash);
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }
}

class _Social {
  final String name;
  final String? url;
  final Color color;
  final Widget mark;
  const _Social(this.name, this.url, this.color, this.mark);
}

/// A simple lettered glyph for platforms Material has no icon for (X, LinkedIn).
class _TextMark extends StatelessWidget {
  final String text;
  const _TextMark(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.0));
  }
}

/// The lower-case "f" of the Facebook mark.
class _FacebookMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text('f',
        style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.0));
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 48, color: AppColors.muted),
            SizedBox(height: 12),
            Text('Social links are on their way.',
                style: TextStyle(color: AppColors.slate, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
