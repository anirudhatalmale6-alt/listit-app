/// Option lists for the Sell form's Vehicle Details section, mirroring the
/// website's `allVehicleAttr` so an app-posted vehicle carries the same
/// structured details a website-posted one does.
library;

const List<String> kFuelTypes = [
  'PETROL',
  'DIESEL',
  'ELECTRIC',
  'HYBRID PETROL',
  'HYBRID DIESEL',
  'PLUGIN HYBRID',
  'CNG',
  'LPG',
  'HYDROGEN',
  'BIOETHANOL',
  'BI-FUEL',
  'DUAL FUEL',
  'OTHER',
];

const List<String> kColours = [
  'BLACK',
  'WHITE',
  'GREY',
  'BLUE',
  'RED',
  'SILVER',
  'GREEN',
  'BROWN',
  'ORANGE',
  'YELLOW',
  'BEIGE',
  'GOLD',
  'OTHER',
];

const List<String> kTransmissions = [
  'Manual',
  'Automatic',
  'CVT',
  'Semi-Automatic',
];

/// A trimmed, sensible body-type list covering cars, vans, bikes, buses and
/// campers (the full website list is exhaustive; these are the common picks).
const List<String> kBodyTypes = [
  'Hatchback',
  'Saloon',
  'Estate',
  'SUV',
  'MPV',
  'Coupe',
  'Convertible',
  'Pickup',
  'Camper',
  'Motorhome',
  'Caravan',
  'Panel Van',
  'Combi Van',
  'Crew Cab',
  'Minibus',
  'Bus',
  'Coach',
  'Naked',
  'Adventure',
  'Scooter',
  'Sports Tourer',
  'Cruiser',
  'Other',
];

const List<String> kDoorOptions = ['2', '3', '4', '5'];

/// Fuel types that are battery-powered, where a battery-range field applies.
bool isBatteryFuel(String fuel) {
  final f = fuel.toUpperCase();
  return f.contains('ELECTRIC') || f.contains('HYDROGEN');
}

/// Model years: this year (or next from September) back 40 years.
List<String> vehicleYears() {
  final now = DateTime.now();
  final start = now.month >= 9 ? now.year + 1 : now.year;
  return [for (var y = start; y >= start - 40; y--) y.toString()];
}
