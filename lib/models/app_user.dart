import '../config/api_config.dart';

/// The signed-in user, parsed from the `user_info` the auth + profile
/// endpoints return. Defensive throughout - the API sends plenty of nullable
/// columns and mixes ints/strings, so every field copes with both.
class AppUser {
  final int id;
  final String name;
  final String email;
  final String? avatar;
  final String vendorType;
  final String? businessName;
  final String? phone;
  final String? location;
  final double rating;
  final int reviews;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.vendorType = 'normal',
    this.businessName,
    this.phone,
    this.location,
    this.rating = 0,
    this.reviews = 0,
  });

  bool get isDealer => vendorType == 'dealer';
  String get displayName =>
      (businessName != null && businessName!.trim().isNotEmpty)
          ? businessName!.trim()
          : name;

  /// First initial(s) for the fallback avatar.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final logo = (j['logo'] ?? '').toString();
    final image = (j['image'] ?? '').toString();
    final raw = logo.isNotEmpty ? logo : image;
    return AppUser(
      id: _asInt(j['id']),
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      avatar: raw.isEmpty ? null : ApiConfig.resolveImage(raw),
      vendorType: (j['vendor_type'] ?? 'normal').toString(),
      businessName: (j['business_name'] ?? '').toString().isEmpty
          ? null
          : j['business_name'].toString(),
      phone: (j['number'] ?? j['phone_contact'] ?? '').toString().isEmpty
          ? null
          : (j['number'] ?? j['phone_contact']).toString(),
      location: (j['location'] ?? '').toString().isEmpty
          ? null
          : j['location'].toString(),
      rating: _asDouble(j['average_rating']),
      reviews: _asInt(j['total_reviews']),
    );
  }

  Map<String, dynamic> toStorage() => {
        'id': id,
        'name': name,
        'email': email,
        'logo': avatar,
        'vendor_type': vendorType,
        'business_name': businessName,
        'number': phone,
        'location': location,
        'average_rating': rating,
        'total_reviews': reviews,
      };
}
