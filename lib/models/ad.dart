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

  factory Ad.fromJson(Map<String, dynamic> json) {
    return Ad(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      price: _asDouble(json['price']),
      oldPrice: _asDouble(json['old_price']),
      images: _parseImages(json['images']),
      location: (json['location'] ?? '').toString(),
      sellerName: (json['full_name'] ?? '').toString(),
      businessName: json['business_name']?.toString(),
      viewCount: _asInt(json['view_count']),
      likeCount: _asInt(json['like_count']),
      isVehicle: _asInt(json['is_vehicle']) == 1,
      isSaved: _asInt(json['isSaved']) == 1,
      underOffer: _asInt(json['under_offer']) == 1,
      vendorType: (json['vendor_type'] ?? 'normal').toString(),
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
