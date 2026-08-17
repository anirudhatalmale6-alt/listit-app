import 'dart:convert';

/// A category-specific attribute (e.g. Property → Bedrooms, Phones → Storage)
/// that the website collects and filters on. Fetched from `admin/attribute`
/// and rendered dynamically in the Sell form and the results Filter sheet, so
/// the app's per-category options always mirror the website.
class AdAttribute {
  final int id;
  final String label;
  final String key; // label lowercased, spaces -> underscores (matches website)
  final String inputType; // select | text | number
  final String type; // dropdown | checkbox | radio
  final List<String> options;
  final bool isFilter; // whether it appears as a filter on results

  const AdAttribute({
    required this.id,
    required this.label,
    required this.key,
    required this.inputType,
    required this.type,
    required this.options,
    required this.isFilter,
  });

  bool get hasOptions => options.isNotEmpty;

  factory AdAttribute.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] ?? '').toString();
    return AdAttribute(
      id: _asInt(json['id']),
      label: label,
      key: label.toLowerCase().replaceAll(' ', '_'),
      inputType: (json['input_type'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      options: _parseOptions(json['options_value']),
      isFilter: _asInt(json['is_filter']) == 1,
    );
  }
}

List<String> _parseOptions(dynamic raw) {
  if (raw == null) return const [];
  dynamic decoded = raw;
  if (raw is String) {
    if (raw.trim().isEmpty) return const [];
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is List) {
    return decoded.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
