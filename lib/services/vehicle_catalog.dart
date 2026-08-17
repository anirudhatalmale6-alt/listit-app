import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// The island's vehicle makes, each with its full model range and a live ad
/// count - bundled as an asset (generated from the DVLA-style make/model master
/// so the make / model picker is instant, works offline and lists every model,
/// like DoneDeal). Each model carries the vehicle types it belongs to (car,
/// bike, van, truck, bus, other) so the picker can show a car buyer only the
/// make's cars, a bike buyer only its bikes, and so on. Model names are the
/// cleaned base (e.g. "FOCUS", "3 SERIES", "C-CLASS"); the backend matches them
/// loosely (LIKE), so they still catch the messier trim-level values stored
/// against each ad.
class CatModel {
  final String model;
  final int count;

  /// Compact vehicle-type tags: c=car, m=motorbike, v=van, t=truck, b=bus,
  /// o=other. A model can carry several (e.g. a make's Transporter is car+van).
  final String types;
  const CatModel(this.model, this.count, this.types);

  bool matches(String? bucket) => bucket == null || types.contains(bucket);
}

class CatMake {
  final String make;
  final int count;
  final String types;
  final List<CatModel> models;
  const CatMake(this.make, this.count, this.types, this.models);

  bool matches(String? bucket) => bucket == null || types.contains(bucket);

  /// This make's models limited to the given section bucket (all if null).
  List<CatModel> modelsFor(String? bucket) =>
      bucket == null ? models : [for (final m in models) if (m.matches(bucket)) m];
}

class VehicleCatalog {
  static List<CatMake>? _cache;

  static Future<List<CatMake>> load() async {
    if (_cache != null) return _cache!;
    try {
      final raw = await rootBundle.loadString('assets/vehicle_catalog.json');
      final list = jsonDecode(raw);
      if (list is! List) return _cache = const [];
      _cache = [
        for (final e in list)
          if (e is Map)
            CatMake(
              (e['k'] ?? '').toString(),
              (e['n'] as num?)?.toInt() ?? 0,
              (e['t'] ?? '').toString(),
              [
                for (final mm in (e['m'] as List? ?? []))
                  if (mm is List && mm.length >= 2)
                    CatModel(
                      mm[0].toString(),
                      (mm[1] as num?)?.toInt() ?? 0,
                      mm.length >= 3 ? mm[2].toString() : '',
                    ),
              ],
            ),
      ];
    } catch (_) {
      _cache = const [];
    }
    return _cache!;
  }

  /// The makes relevant to a section bucket (only those that have at least one
  /// model of that type), keeping the generated order (ad-count first, then
  /// alphabetical). Pass null to get every make.
  static List<CatMake> makesFor(List<CatMake> all, String? bucket) =>
      bucket == null ? all : [for (final m in all) if (m.matches(bucket)) m];
}

/// Which vehicle-type bucket a category should filter the make / model list to.
/// Cars For Sale -> cars, Motorbikes -> bikes, Vans -> vans, etc. Anything not
/// mapped (campers, plant, quads, caravans) returns null = show everything, so
/// the picker never hides options for a section we haven't classified.
String? vehicleBucketForCategory(int? categoryId) {
  switch (categoryId) {
    case 89: // Cars For Sale
    case 183: // Electric Cars
    case 132: // Rally Cars
    case 137: // Vintage Cars
    case 126: // Modified Cars
    case 83: // Damaged Repairables
    case 84: // Cars For Breaking
      return 'c';
    case 128: // Motorbikes
    case 133: // Scooters
    case 136: // Vintage Bikes
    case 131: // Quads
      return 'm';
    case 125: // Vans & Commercials
      return 'v';
    case 135: // Trucks
      return 't';
    case 124: // Coaches & Buses
      return 'b';
    default:
      return null;
  }
}
