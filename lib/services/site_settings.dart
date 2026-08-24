import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import 'api_service.dart';

/// Site-wide settings pulled from the same source the website uses (its
/// `admin/setting` endpoint): social links, banner images, contact details.
///
/// Kept in a [ValueNotifier] so widgets can rebuild when the values arrive, and
/// so anything the site owner changes on the website shows up in the app too.
class SiteSettings {
  SiteSettings._();

  static final ValueNotifier<Map<String, String>> values =
      ValueNotifier<Map<String, String>>({});

  /// Fetch once (best-effort). Never throws - if it fails the app just falls
  /// back to its bundled defaults.
  static Future<void> load(ApiService api) async {
    try {
      final map = await api.fetchSiteSettings();
      if (map.isNotEmpty) values.value = map;
    } catch (_) {/* keep whatever we have; callers have fallbacks */}
  }

  static String? _get(String key) {
    final v = values.value[key];
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  // --- Social links (mirror the website footer) ----------------------------
  static String? get facebook => _get('facebook');
  static String? get twitter => _get('twitter');
  static String? get instagram => _get('Instagram');
  static String? get youtube => _get('youtube');
  static String? get linkedIn => _get('linkedIn');

  // --- Home banner image ----------------------------------------------------
  /// The marketplace banner shown on the website home, resolved to a full URL.
  static String? get homeBanner {
    final raw = _get('home');
    return raw == null ? null : ApiConfig.resolveImage(raw);
  }

  /// The Property section banner (the website's own `property` setting), so the
  /// Property tab's hero shows a property image rather than the generic one.
  static String? get propertyBanner {
    final raw = _get('property');
    return raw == null ? null : ApiConfig.resolveImage(raw);
  }

  /// The Farming section banner (the website's own `farming` setting).
  static String? get farmingBanner {
    final raw = _get('farming');
    return raw == null ? null : ApiConfig.resolveImage(raw);
  }
}
