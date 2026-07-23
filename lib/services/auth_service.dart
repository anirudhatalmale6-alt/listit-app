import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import 'api_service.dart';

/// Owns the signed-in session: the JWT and the current [AppUser]. Persists both
/// to shared_preferences so the user stays logged in across launches (the token
/// lasts 2 days server-side). [ApiService] reads `token` through a closure to
/// attach the Authorization header, which keeps the two services decoupled.
class AuthService extends ChangeNotifier {
  static const _kToken = 'auth_token';
  static const _kUser = 'auth_user';

  ApiService? _api;
  String? _token;
  AppUser? _user;

  String? get token => _token;
  AppUser? get user => _user;
  bool get isLoggedIn => _token != null && _user != null;

  /// Wire the HTTP client this service drives for login/register/profile.
  void bind(ApiService api) => _api = api;

  /// Restore a persisted session on startup. Best-effort - a refresh failure
  /// (offline, expired token) just leaves the cached user in place; a hard 401
  /// on the next gated call will prompt a re-login.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    final rawUser = prefs.getString(_kUser);
    if (rawUser != null) {
      try {
        _user = AppUser.fromJson(jsonDecode(rawUser) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }
    if (_token != null && _user != null) notifyListeners();
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await _api!.register(name: name, email: email, password: password);
    await _apply(res);
  }

  Future<void> login({required String email, required String password}) async {
    final res = await _api!.login(email: email, password: password);
    await _apply(res);
  }

  /// Sign in with a Facebook access token obtained on the device. The server
  /// verifies it and returns a normal Listit session, so from here it behaves
  /// exactly like [login]/[register].
  Future<void> loginWithFacebook(String accessToken) async {
    final res = await _api!.facebookLogin(accessToken: accessToken);
    await _apply(res);
  }

  /// Pull the freshest profile for the signed-in user (ratings, avatar, ...).
  Future<void> refreshProfile() async {
    if (!isLoggedIn) return;
    try {
      final u = await _api!.fetchProfile();
      _user = u;
      await _persist();
      notifyListeners();
    } catch (_) {
      // Non-fatal: keep the cached user.
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    notifyListeners();
  }

  Future<void> _apply(AuthResult res) async {
    _token = res.token;
    _user = res.user;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString(_kToken, _token!);
    if (_user != null) {
      await prefs.setString(_kUser, jsonEncode(_user!.toStorage()));
    }
  }
}
