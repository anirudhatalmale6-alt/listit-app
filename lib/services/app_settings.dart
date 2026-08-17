import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small device-level preferences that aren't tied to the account. Right now
/// just handedness: whether tick boxes / controls sit on the left (default,
/// for right-hand use) or the right (for left-hand use). Exposed as a
/// [ValueNotifier] so any open screen updates the moment it's toggled.
class AppSettings {
  AppSettings._();

  static const _leftHandedKey = 'left_handed';

  /// false = controls on the left (right-hand use); true = on the right.
  static final ValueNotifier<bool> leftHanded = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      leftHanded.value = prefs.getBool(_leftHandedKey) ?? false;
    } catch (_) {
      // Defaults are fine if prefs can't be read.
    }
  }

  static Future<void> setLeftHanded(bool v) async {
    leftHanded.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_leftHandedKey, v);
    } catch (_) {/* best-effort persistence */}
  }
}
