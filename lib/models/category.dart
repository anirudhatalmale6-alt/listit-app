import 'dart:convert';

import '../config/api_config.dart';

/// A node in the Listit category tree. The `/admin/category-new` endpoint
/// returns a flat list; `parent_id == 0` marks a top-level section (Property,
/// Cars & Motors, ...). We build the tree client-side from `parentId`.
class Category {
  final int id;
  final String name;
  final String slug;
  final int parentId;
  final bool isVehicle;
  final String imageUrl;
  final int adCount;

  /// Which vehicle-detail fields this category collects, e.g.
  /// `{make: true, model: true, body_type: true, ...}`. Comes from the
  /// category's `vehicle_data` JSON and drives the Sell form's vehicle
  /// section, exactly like the website. Empty for non-vehicle categories.
  final Map<String, bool> vehicleFields;

  /// Whether the category offers finance (the "Finance" button on ads).
  final bool showFinance;

  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.parentId,
    required this.isVehicle,
    required this.imageUrl,
    required this.adCount,
    this.vehicleFields = const {},
    this.showFinance = false,
  });

  bool get isTopLevel => parentId == 0;

  /// True if this vehicle category asks for [field] (falls back to true when
  /// the category has no field map, so a bare vehicle still shows the basics).
  bool wantsVehicleField(String field) =>
      vehicleFields.isEmpty ? true : (vehicleFields[field] ?? false);

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      parentId: _asInt(json['parent_id']),
      isVehicle: _asInt(json['is_vehicle']) == 1,
      imageUrl: ApiConfig.resolveImage(json['image']?.toString()),
      adCount: _asInt(json['ad_count']),
      vehicleFields: _parseVehicleData(json['vehicle_data']),
      showFinance: _asInt(json['show_finance']) == 1,
    );
  }
}

/// The `vehicle_data` value is a JSON string like `{"make":1,"model":1,...}`.
/// Parse it into a `{key: bool}` map; anything unparseable yields an empty map.
Map<String, bool> _parseVehicleData(dynamic raw) {
  if (raw == null) return const {};
  Map<String, dynamic>? m;
  if (raw is Map) {
    m = raw.cast<String, dynamic>();
  } else if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) m = decoded.cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }
  if (m == null) return const {};
  return {for (final e in m.entries) e.key: _asInt(e.value) == 1};
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
