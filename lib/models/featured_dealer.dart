import '../config/api_config.dart';

/// A dealer/estate-agent surfaced in the "Featured Dealers" strip. Backed by
/// the `/api/user/featured-dealers?sector=motors|property` endpoint, which only
/// returns businesses with live, paid (featured) stock.
class FeaturedDealer {
  final int id;
  final String name;
  final String logo;
  final double rating;
  final int reviews;
  final int stock;
  final List<FeaturedAd> ads;

  const FeaturedDealer({
    required this.id,
    required this.name,
    required this.logo,
    required this.rating,
    required this.reviews,
    required this.stock,
    required this.ads,
  });

  factory FeaturedDealer.fromJson(Map<String, dynamic> json) {
    return FeaturedDealer(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      logo: ApiConfig.resolveImage(json['logo']?.toString()),
      rating: _asDouble(json['average_rating']),
      reviews: _asInt(json['total_reviews']),
      stock: _asInt(json['total_stock']),
      ads: (json['ads'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FeaturedAd.fromJson)
          .toList(),
    );
  }

  /// A wide banner image for the single "Featured Dealer" card: the dealer's
  /// top stock photo (we don't store a separate storefront shot).
  String get bannerImage {
    for (final a in ads) {
      if (a.image.isNotEmpty) return a.image;
    }
    return '';
  }
}

/// One of a featured dealer's showcased listings (thumbnail + price).
class FeaturedAd {
  final int id;
  final String title;
  final double price;
  final String image;

  const FeaturedAd({
    required this.id,
    required this.title,
    required this.price,
    required this.image,
  });

  factory FeaturedAd.fromJson(Map<String, dynamic> json) {
    return FeaturedAd(
      id: _asInt(json['id']),
      title: (json['title'] ?? '').toString(),
      price: _asDouble(json['price']),
      image: ApiConfig.resolveImage(json['image']?.toString()),
    );
  }
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
