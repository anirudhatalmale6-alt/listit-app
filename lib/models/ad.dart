import 'dart:convert';
import '../config/api_config.dart';

/// A single listing. Backs both the swipe deck (search feed) and the detail
/// screen. The API is a little loose with types across endpoints - price
/// arrives as a string, and `images` is a JSON-encoded string in the search
/// feed but a real array in the ad-detail payload - so parsing is defensive.
class Ad {
  final int id;
  final int userId;
  final String title;
  final String description;
  final double price;
  final double oldPrice;
  final List<String> images;
  final String location;
  final String sellerName;
  final String? businessName;
  final int viewCount;
  final int likeCount;
  final bool isVehicle;
  final bool isSaved;
  final bool underOffer;
  final String vendorType;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const Ad({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.price,
    required this.oldPrice,
    required this.images,
    required this.location,
    required this.sellerName,
    required this.businessName,
    required this.viewCount,
    required this.likeCount,
    required this.isVehicle,
    required this.isSaved,
    required this.underOffer,
    required this.vendorType,
    required this.createdAt,
    required this.raw,
  });

  bool get hasDiscount => oldPrice > price && price > 0;
  bool get isFree => price <= 0;
  bool get isDealer => vendorType == 'dealer' || (businessName?.isNotEmpty ?? false);
  String get displayName =>
      (businessName != null && businessName!.isNotEmpty) ? businessName! : sellerName;
  String? get coverImage => images.isNotEmpty ? images.first : null;

  /// True when this ad sits under the Property section (top-level id 106).
  /// Used so an estate agent reads as "Agent" rather than "Trade".
  bool get isProperty {
    final c = (raw['categories'] ?? '').toString();
    return c.split(',').map((e) => e.trim()).contains('106');
  }

  /// The seller-type badge shown on cards: estate agents on Property read as
  /// "Agent", other businesses as "Trade".
  String get traderLabel => isProperty ? 'Agent' : 'Trade';

  /// True while this listing is inside a paid Spotlight window
  /// (`spotlight_starts` .. `spotlight_ends`). Spotlight ads get the amber
  /// glow + "Spotlight" badge on their card, exactly like the website.
  bool get isSpotlight {
    final ends = DateTime.tryParse((raw['spotlight_ends'] ?? '').toString());
    if (ends == null) return false;
    final now = DateTime.now().toUtc();
    final starts = DateTime.tryParse((raw['spotlight_starts'] ?? '').toString());
    if (starts != null && starts.toUtc().isAfter(now)) return false;
    return ends.toUtc().isAfter(now);
  }

  /// The listing's lifecycle status (place_ads.status): 1 live, 2 sold,
  /// 0 pending, 3 blocked, 4 removed, 5 sold elsewhere. Drives the chip on the
  /// owner's "My listings" screen.
  int get status => _asInt(raw['status']);
  String get statusLabel {
    switch (status) {
      case 1:
        return 'Live';
      case 2:
      case 5:
        return 'Sold';
      case 3:
        return 'Blocked';
      case 4:
        return 'Removed';
      default:
        return 'Pending';
    }
  }

  /// The seller's contact preferences (`allow_contact` is a CSV where "1"
  /// means in-app messaging is switched on). Empty/unknown falls back to
  /// allowed, since chat is the app's primary contact route.
  List<String> get _allowContact {
    final c = (raw['allow_contact'] ?? '').toString();
    return c.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  bool get allowsMessaging {
    final list = _allowContact;
    return list.isEmpty || list.contains('1');
  }

  /// The seller lets buyers phone/text them (`"2"` in `allow_contact`, the
  /// site's "Phone/Text" option). Empty falls back to on, matching the site's
  /// default of both channels enabled.
  bool get allowsCalling {
    final list = _allowContact;
    return list.isEmpty || list.contains('2');
  }

  /// Buyers can send a price offer on anything except Property (estate agents
  /// take enquiries, not offers), mirroring the website's `hideOffer` rule.
  bool get allowsOffers => !isProperty;

  /// The dealer's logo URL, resilient across endpoints: the search feed carries
  /// it top-level (`logo` / `seller_image`), the detail under `userDetails`.
  /// `logo` is the brand mark (what we want); the backend stores it as a Google
  /// `s2/favicons` link for agents without an uploaded logo, but that endpoint
  /// 301s to an HTML consent page and won't render in-app - so we rewrite it to
  /// gstatic's `faviconV2`, which returns a direct PNG of the same logo.
  String get dealerLogo {
    final ud = raw['userDetails'];
    final u = ud is Map ? ud : const {};
    final url = [
      raw['logo'], u['logo'], raw['seller_image'], u['image'], raw['image'],
    ]
        .map((e) => (e ?? '').toString())
        .firstWhere((e) => e.isNotEmpty && e != 'null', orElse: () => '');
    if (url.isEmpty) return '';
    if (url.contains('google.com/s2/favicons')) {
      final domain = RegExp(r'domain=([^&]+)').firstMatch(url)?.group(1) ?? '';
      if (domain.isNotEmpty) {
        return 'https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON'
            '&fallback_opts=TYPE,SIZE,URL&url=https://$domain&size=128';
      }
    }
    return url;
  }

  factory Ad.fromJson(Map<String, dynamic> json) {
    // The seller's identity (vendor_type / business_name / name) sits at the
    // top level in the search feed but only under `userDetails` in the ad-detail
    // payload. Read the top level first, then fall back to userDetails, so an
    // estate agent reads as "Agent" (not "Private seller") on the detail page.
    final ud = json['userDetails'];
    final u = ud is Map ? ud : const {};
    String? pick(String key) {
      final a = json[key];
      if (a != null && a.toString().trim().isNotEmpty) return a.toString();
      final b = u[key];
      if (b != null && b.toString().trim().isNotEmpty) return b.toString();
      return null;
    }

    return Ad(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      price: _asDouble(json['price']),
      oldPrice: _asDouble(json['old_price']),
      images: _parseImages(json['images']),
      location: (json['location'] ?? '').toString(),
      sellerName: pick('full_name') ?? pick('name') ?? '',
      businessName: pick('business_name'),
      viewCount: _asInt(json['view_count']),
      likeCount: _asInt(json['like_count']),
      isVehicle: _asInt(json['is_vehicle']) == 1,
      isSaved: _asInt(json['isSaved']) == 1,
      underOffer: _asInt(json['under_offer']) == 1,
      vendorType: pick('vendor_type') ?? 'normal',
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      raw: json,
    );
  }

  /// Handy for `flutter_card_swiper` which needs stable identity when a card
  /// is re-inserted (e.g. an undo).
  @override
  bool operator ==(Object other) => other is Ad && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

List<String> _parseImages(dynamic value) {
  if (value == null) return const [];
  List<dynamic> list;
  if (value is List) {
    list = value;
  } else if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      list = decoded is List ? decoded : [decoded];
    } catch (_) {
      list = [value];
    }
  } else {
    return const [];
  }
  return list
      .map((e) => ApiConfig.resolveImage(e?.toString()))
      .where((e) => e.isNotEmpty)
      .toList();
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double _asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
