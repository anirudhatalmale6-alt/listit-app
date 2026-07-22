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

  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.parentId,
    required this.isVehicle,
    required this.imageUrl,
    required this.adCount,
  });

  bool get isTopLevel => parentId == 0;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      parentId: _asInt(json['parent_id']),
      isVehicle: _asInt(json['is_vehicle']) == 1,
      imageUrl: ApiConfig.resolveImage(json['image']?.toString()),
      adCount: _asInt(json['ad_count']),
    );
  }
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
