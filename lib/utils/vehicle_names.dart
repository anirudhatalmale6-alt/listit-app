/// Turns the raw, ALL-CAPS make/model values stored against ads into properly
/// cased display names: acronym makes stay upper ("BMW", "VW", "DS", "MG"),
/// model codes read right ("X6", "A1", "ID3", "118i", "320d", "2 Series"), and
/// ordinary words are title-cased ("Ford", "Golf", "Mercedes-Benz").
///
/// Only for display - the raw value is still what gets sent to the backend, so
/// the filter match stays exact.
String prettyVehicleName(String raw) {
  // Drop dots so "ID.3" reads as "ID3"; base model names never carry a
  // meaningful decimal (the trim/engine part is stripped upstream).
  final s = raw.replaceAll('.', '').trim();
  if (s.isEmpty) return raw.trim();
  return s.split(RegExp(r'\s+')).map(_word).join(' ');
}

String _word(String w) => w.split('-').map(_part).join('-');

String _part(String p) {
  if (p.isEmpty) return p;
  final hasDigit = p.contains(RegExp(r'[0-9]'));
  if (hasDigit) {
    // Letter-led codes read best fully upper (X6, A1, E93, ID3, Q5); digit-led
    // ones keep the digits and lower-case the suffix (118i, 320d, 2).
    if (RegExp(r'^[A-Za-z]').hasMatch(p)) return p.toUpperCase();
    return p.replaceAllMapped(
        RegExp(r'[A-Za-z]+'), (m) => m[0]!.toLowerCase());
  }
  // All letters: short vowel-less tokens are acronyms (BMW, VW, DS, MG, JCB).
  final vowel = RegExp(r'[AEIOU]', caseSensitive: false);
  if (!vowel.hasMatch(p) && p.length <= 3) return p.toUpperCase();
  return p[0].toUpperCase() + p.substring(1).toLowerCase();
}
