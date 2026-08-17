/// The distinct vehicle attribute values on the island (makes, fuel types,
/// body types, colours) with how many live ads carry each - straight from the
/// backend's `popular_searches` facet query. Backs the car-search make list
/// and the vehicle filter sections.
class VehicleFacets {
  /// e.g. { 'FORD': 158, 'BMW': 124, ... }, busiest first.
  final List<FacetValue> makes;
  final List<FacetValue> fuelTypes;
  final List<FacetValue> bodyTypes;
  final List<FacetValue> colours;

  const VehicleFacets({
    this.makes = const [],
    this.fuelTypes = const [],
    this.bodyTypes = const [],
    this.colours = const [],
  });

  bool get isEmpty => makes.isEmpty;

  factory VehicleFacets.fromRows(List<dynamic> rows) {
    final makes = <FacetValue>[];
    final fuel = <FacetValue>[];
    final body = <FacetValue>[];
    final colour = <FacetValue>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final type = (r['type'] ?? '').toString();
      final value = (r['value'] ?? '').toString().trim();
      if (value.isEmpty) continue;
      final count = r['count'] is num
          ? (r['count'] as num).toInt()
          : int.tryParse('${r['count']}') ?? 0;
      final fv = FacetValue(value, count);
      switch (type) {
        case 'make':
          makes.add(fv);
          break;
        case 'fuel_type':
          fuel.add(fv);
          break;
        case 'body_type':
          body.add(fv);
          break;
        case 'colour':
          colour.add(fv);
          break;
      }
    }
    return VehicleFacets(
      makes: makes,
      fuelTypes: fuel,
      bodyTypes: body,
      colours: colour,
    );
  }
}

class FacetValue {
  final String value;
  final int count;
  const FacetValue(this.value, this.count);
}
