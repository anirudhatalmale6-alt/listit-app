import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the user's most recent keyword searches on the device, so the
/// Search screen can offer them the way DoneDeal shows "My Last Search".
class RecentSearches {
  static const _key = 'recent_searches';
  static const _max = 12;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  /// Add a term to the top, de-duplicating (case-insensitive) and capping.
  static Future<void> add(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((e) => e.toLowerCase() == t.toLowerCase());
    list.insert(0, t);
    if (list.length > _max) list.removeRange(_max, list.length);
    await prefs.setStringList(_key, list);
  }

  static Future<void> remove(String term) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((e) => e.toLowerCase() == term.toLowerCase());
    await prefs.setStringList(_key, list);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
