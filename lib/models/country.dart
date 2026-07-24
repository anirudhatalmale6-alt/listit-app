/// A phone country the seller can pick when entering a contact number.
///
/// [iso] is the ISO-3166 alpha-2 the backend stores as `country_code`
/// (IM / GB / IE). [dial] is the dialling code the backend stores as `flag` /
/// `phone_code`. The Isle of Man and the UK share +44 — the flag picker is how
/// we tell an IoM (01624 / 07624) seller apart from a mainland UK one.
class PhoneCountry {
  final String iso;
  final String dial;
  final String name;
  final String hint; // sample local number shown in the field

  const PhoneCountry({
    required this.iso,
    required this.dial,
    required this.name,
    required this.hint,
  });
}

/// Ordered so the Isle of Man (our home market) leads. Kept short on purpose —
/// these cover essentially every Listit seller; add more here if needed.
const List<PhoneCountry> kPhoneCountries = [
  PhoneCountry(iso: 'IM', dial: '44', name: 'Isle of Man', hint: '07624 123456'),
  PhoneCountry(iso: 'GB', dial: '44', name: 'United Kingdom', hint: '07700 900000'),
  PhoneCountry(iso: 'IE', dial: '353', name: 'Ireland', hint: '085 123 4567'),
];

// Isle of Man — our home market and the default flag.
const PhoneCountry kDefaultCountry =
    PhoneCountry(iso: 'IM', dial: '44', name: 'Isle of Man', hint: '07624 123456');

/// Best-effort match of a stored (country_code, dial) back to one of our
/// options so an existing number pre-selects the right flag. Falls back to the
/// Isle of Man.
PhoneCountry countryFor({String? iso, String? dial}) {
  final i = (iso ?? '').toUpperCase();
  if (i.isNotEmpty) {
    for (final c in kPhoneCountries) {
      if (c.iso == i) return c;
    }
  }
  final d = (dial ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.isNotEmpty) {
    for (final c in kPhoneCountries) {
      if (c.dial == d) return c;
    }
  }
  return kDefaultCountry;
}
