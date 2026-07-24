/// A listing plan (Lite, Excel, Premium, ...) as returned by `/api/user/plan`.
/// The app only needs the free "Lite" tier for a first listing, but the whole
/// list is parsed so we can pick the cheapest available plan for a category and
/// show upgrade options later.
class Plan {
  final int id;
  final String name;
  final double price;
  final int days;
  final int photos;
  final bool recommended;

  const Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.days,
    required this.photos,
    required this.recommended,
  });

  bool get isFree => price <= 0;

  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  static double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: _asInt(j['id']),
        // The API mixes camelCase (planName) and snake_case depending on route.
        name: (j['planName'] ?? j['plan_name'] ?? '').toString(),
        price: _asDouble(j['price']),
        days: _asInt(j['daysOfListing'] ?? j['days_of_listing']),
        photos: _asInt(j['numberOfPhotos'] ?? j['number_of_photos']),
        recommended: _asInt(j['recommended']) == 1,
      );
}
