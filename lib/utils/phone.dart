/// Phone-number normalisation, kept in lock-step with the website
/// (`src/constants/commonFunctions.jsx`). Dealers and sellers store their
/// numbers in a handful of inconsistent shapes (00-intl, trunk-0 landline,
/// bare local, already-prefixed) so every dial/WhatsApp link runs through here
/// first. Returns E.164 digits WITHOUT the leading + — the wrappers add it.
String normPhoneDigits(dynamic number, dynamic flag) {
  if (number == null) return '';
  var n = number.toString().replaceAll(RegExp(r'\D'), ''); // digits only
  if (n.isEmpty) return '';
  final cc = (flag == null ? '' : flag.toString()).replaceAll(RegExp(r'\D'), '');
  final code = cc.isEmpty ? '44' : cc;

  // 00 = international access prefix -> the rest already includes the CC.
  if (n.startsWith('00')) return n.substring(2);
  // Drop a single national trunk 0 (01624..., 07624...).
  if (n.startsWith('0')) n = n.substring(1);
  // Already carries the country code (441624..., 447624...).
  if (n.startsWith(code) && n.length >= code.length + 6) return n;
  // Isle of Man national numbers entered without a trunk 0 (1624..., 7624...).
  if (code == '44' && RegExp(r'^(1624|7624)').hasMatch(n)) return code + n;
  // Bare local number missing the IoM area code (420420 -> 1624 420420).
  if (code == '44' && n.length <= 7) return '${code}1624$n';
  // Anything else: just prefix the country code.
  return code + n;
}

/// International number with a leading + for `tel:` links and display.
String toIntlPhone(dynamic number, dynamic flag) {
  final d = normPhoneDigits(number, flag);
  return d.isEmpty ? '' : '+$d';
}

/// Digits-only international number for wa.me / WhatsApp deep links (no +).
String toWaNumber(dynamic number, dynamic flag) => normPhoneDigits(number, flag);
