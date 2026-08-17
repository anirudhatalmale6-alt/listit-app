import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ad.dart';

/// A compact snapshot of an ad the user has opened, kept on the device so the
/// "Recently Viewed" list can show it instantly (title, price, photo) and open
/// straight back into the full listing.
class ViewedAd {
  final int id;
  final String title;
  final double price;
  final String image;
  final String location;

  const ViewedAd({
    required this.id,
    required this.title,
    required this.price,
    required this.image,
    required this.location,
  });

  bool get isFree => price <= 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': price,
        'image': image,
        'location': location,
      };

  static ViewedAd fromJson(Map<String, dynamic> j) => ViewedAd(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        price: (j['price'] as num?)?.toDouble() ??
            double.tryParse('${j['price']}') ??
            0,
        image: (j['image'] ?? '').toString(),
        location: (j['location'] ?? '').toString(),
      );
}

/// Remembers the ads the user has looked at (most recent first), DoneDeal's
/// "Browsing history". Stored on the device, so it works signed in or out.
class RecentlyViewed {
  static const _key = 'recently_viewed';
  static const _max = 40;

  static Future<List<ViewedAd>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final out = <ViewedAd>[];
    for (final s in raw) {
      try {
        final j = jsonDecode(s);
        if (j is Map<String, dynamic>) out.add(ViewedAd.fromJson(j));
      } catch (_) {/* skip a corrupt entry */}
    }
    return out;
  }

  /// Record an opened ad at the top of the list, de-duplicating by id.
  static Future<void> add(Ad ad) async {
    if (ad.id <= 0 || ad.title.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s)['id'] as num?)?.toInt() == ad.id;
      } catch (_) {
        return false;
      }
    });
    raw.insert(
      0,
      jsonEncode(ViewedAd(
        id: ad.id,
        title: ad.title,
        price: ad.price,
        image: ad.coverImage ?? '',
        location: ad.location,
      ).toJson()),
    );
    if (raw.length > _max) raw.removeRange(_max, raw.length);
    await prefs.setStringList(_key, raw);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
