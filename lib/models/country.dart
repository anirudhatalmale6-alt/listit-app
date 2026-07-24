import '../utils/phone.dart';

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

/// Detect Isle of Man vs UK straight from what the user typed, per the Manx
/// numbering rule: ONLY +441624 (01624 landline) and +447624 (07624 mobile)
/// are Isle of Man — every other +44 number is UK. Returns null while there
/// still aren't enough digits to decide, or when the number looks non-+44
/// (e.g. an Ireland +353 number), so the caller keeps the current selection.
PhoneCountry? detectUkOrManx(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  // Peel any international / trunk prefix down to the national number.
  if (d.startsWith('0044')) {
    d = d.substring(4);
  } else if (d.startsWith('44')) {
    d = d.substring(2);
  } else if (d.startsWith('353')) {
    return null; // an Ireland number — leave the flag as the user set it
  }
  if (d.startsWith('0')) d = d.substring(1);
  if (d.length < 4) return null; // not enough to tell an area code yet
  if (d.startsWith('1624') || d.startsWith('7624')) return kDefaultCountry; // IoM
  return kPhoneCountries[1]; // United Kingdom
}

/// ISO-2 flag code for a stored number (for a FlagBadge), per the Manx rule:
/// only 441624 / 447624 are Isle of Man; any other +44 is UK. Falls back to the
/// stored country_code, then Isle of Man.
String phoneFlagIso(dynamic number, dynamic flag, [String? countryCode]) {
  final d = normPhoneDigits(number, flag);
  if (d.startsWith('441624') || d.startsWith('447624')) return 'im';
  if (d.startsWith('44')) return 'gb';
  final cc = (countryCode ?? '').trim().toLowerCase();
  return cc.isNotEmpty ? cc : 'im';
}

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
