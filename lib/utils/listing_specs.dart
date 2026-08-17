import '../models/ad.dart';

/// The short "key detail" chips DoneDeal shows under a listing - beds/baths/
/// area/type for property, year/mileage/fuel/transmission for vehicles. Kept in
/// one place so the card and the detail header read identically. Property specs
/// are parsed from the title + description (our property ads don't carry
/// structured bed/bath attributes), mirroring the website's card.
List<String> specChipsFor(Ad ad) {
  if (ad.isProperty) return propertySpecChips(ad);
  if (ad.isVehicle) return vehicleSpecChips(ad);
  return const [];
}

String _grouped(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _titleCase(String t) => t.isEmpty
    ? t
    : t
        .toLowerCase()
        .split(RegExp(r'[\s-]'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(t.contains('-') ? '-' : ' ');

/// Vehicle chips from the ad's `vehicleData` (year, mileage, fuel, transmission).
List<String> vehicleSpecChips(Ad ad) {
  final vd = ad.raw['vehicleData'];
  final v = vd is Map ? vd : const {};
  String s(dynamic x) {
    final t = (x ?? '').toString().trim();
    return (t == '-' || t.toLowerCase() == 'null') ? '' : t;
  }

  final chips = <String>[];
  final year = s(v['year']);
  if (year.isNotEmpty) chips.add(year);

  final mil = s(v['milage']);
  if (mil.isNotEmpty) {
    final n = int.tryParse(mil);
    final unit = s(v['milage_unit']).toLowerCase().startsWith('k') ? 'km' : 'mi';
    chips.add('${n != null ? _grouped(n) : mil} $unit');
  }

  final fuel = s(v['fuel_type']);
  if (fuel.isNotEmpty) chips.add(_titleCase(fuel));

  final trans = s(v['transmission']);
  if (trans.isNotEmpty) chips.add(_titleCase(trans));

  return chips;
}

final _bedsRe = RegExp(r'(\d+)\s*bed', caseSensitive: false);
final _bathsRe = RegExp(r'(\d+)\s*bath', caseSensitive: false);
// The unit is captured, not just the number. Isle of Man property is nearly
// always advertised in square feet, and the old pattern threw the unit away and
// printed "m²" on everything — so 9000 sq ft showed as 9000 m².
final _areaRe = RegExp(
    r'(\d[\d,]*(?:\.\d+)?)\s*(sq\.?\s*ft|sqft|ft²|sq\.?\s*m|m²|sqm)',
    caseSensitive: false);
final _typeRe = RegExp(
    r'(semi[\s-]?detached|end of terrace|mid[\s-]?terrace|detached|terrace(?:d)?|bungalow|townhouse|apartment|duplex|cottage|studio|penthouse|maisonette|flat|house)',
    caseSensitive: false);
// Bare land / plots shouldn't show beds or baths, even if a number slips in.
final _landRe = RegExp(
    r'building plot|development plot|development site|plot of land|land at|lifestyle land|paddock|site with|agricultural land',
    caseSensitive: false);

/// Property chips parsed from the title + description: beds, baths, area, type.
List<String> propertySpecChips(Ad ad) {
  final text = '${ad.title}\n${ad.description}';
  final isLand = _landRe.hasMatch(text) && !RegExp(r'new build', caseSensitive: false).hasMatch(text);

  final chips = <String>[];
  if (!isLand) {
    final beds = _bedsRe.firstMatch(text)?.group(1);
    if (beds != null) chips.add('$beds Bed');
    final baths = _bathsRe.firstMatch(text)?.group(1);
    if (baths != null) chips.add('$baths Bath');
  }
  final area = _areaRe.firstMatch(text);
  if (area != null) {
    final unit = area.group(2)!.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
    final isFeet = unit.contains('ft');
    chips.add('${area.group(1)} ${isFeet ? 'sq ft' : 'm²'}');
  }
  final type = _typeRe.firstMatch(text)?.group(1);
  if (type != null) {
    var t = _titleCase(type);
    if (RegExp(r'^semi', caseSensitive: false).hasMatch(type)) t = 'Semi-detached';
    if (isLand) return ['Land'];
    chips.add(t);
  } else if (isLand) {
    return ['Land'];
  }
  return chips;
}
