import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/ad.dart';
import '../models/app_user.dart';
import '../models/category.dart';
import '../models/plan.dart';

/// Result of a search page - the ads plus the total so the UI can show
/// "718 in Cars & Motors" and know when to stop paginating.
class SearchResult {
  final List<Ad> ads;
  final int total;
  const SearchResult(this.ads, this.total);
}

/// A successful login/register - the JWT plus the user it belongs to.
class AuthResult {
  final String token;
  final AppUser user;
  const AuthResult(this.token, this.user);
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Thin, dependency-light client over the live Listit API. Every method
/// unwraps the standard `{ status, message, data }` envelope the backend
/// returns and throws [ApiException] with a readable message on failure.
class ApiService {
  ApiService({http.Client? client, String? Function()? getToken})
      : _client = client ?? http.Client() {
    _getToken = getToken;
  }

  final http.Client _client;

  /// Supplies the current JWT (from AuthService) so gated calls can attach the
  /// Authorization header without this client owning session state.
  String? Function()? _getToken;

  static const Duration _timeout = Duration(seconds: 20);

  Map<String, String> get _headers {
    final h = {'Content-Type': 'application/json'};
    final token = _getToken?.call();
    if (token != null && token.isNotEmpty) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Map<String, dynamic> _unwrap(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('Server error (${res.statusCode}). Please try again.');
    }
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw ApiException('Unexpected response from server.');
    }
    if (body['status'] == 0) {
      throw ApiException((body['message'] ?? 'Request failed').toString());
    }
    final data = body['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// Top-level marketplace sections (Property, Cars & Motors, ...), sorted by
  /// ad count so the busiest categories lead.
  Future<List<Category>> fetchTopCategories() async {
    final res = await _client
        .get(Uri.parse(ApiConfig.categories))
        .timeout(_timeout);
    final data = _unwrap(res);
    final result = (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Category.fromJson)
        .where((c) => c.isTopLevel && c.name.isNotEmpty)
        .toList();
    result.sort((a, b) => b.adCount.compareTo(a.adCount));
    return result;
  }

  /// One page of the filtered feed. `category` is a slug ("cars-and-motors")
  /// or "all" for everything. Extra [filters] (keyword, price range, ...) are
  /// merged into the POST body and passed straight through to the backend.
  Future<SearchResult> search({
    String category = 'all',
    int page = 1,
    int limit = 20,
    Map<String, dynamic> filters = const {},
  }) async {
    final body = <String, dynamic>{
      'category': category,
      'page': page,
      'limit': limit,
      ...filters,
    };
    final res = await _client
        .post(
          Uri.parse(ApiConfig.search),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    final data = _unwrap(res);
    final ads = (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Ad.fromJson)
        .toList();
    final total = data['total'] is num
        ? (data['total'] as num).toInt()
        : int.tryParse('${data['total']}') ?? ads.length;
    return SearchResult(ads, total);
  }

  /// Full detail for one listing - richer than the search row (all photos,
  /// seller details, attributes).
  Future<Ad> fetchAd(int id) async {
    final res = await _client
        .get(Uri.parse(ApiConfig.adDetail(id)))
        .timeout(_timeout);
    final data = _unwrap(res);
    return Ad.fromJson(data);
  }

  // --- Auth ----------------------------------------------------------------

  AuthResult _authResult(Map<String, dynamic> data) {
    final token = (data['token'] ?? '').toString();
    final info = data['user_info'];
    if (token.isEmpty || info is! Map<String, dynamic>) {
      throw ApiException('Unexpected sign-in response.');
    }
    return AuthResult(token, AppUser.fromJson(info));
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.register),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
            'confirm_password': password,
          }),
        )
        .timeout(_timeout);
    return _authResult(_unwrap(res));
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.login),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);
    return _authResult(_unwrap(res));
  }

  /// Exchange a Facebook user access token for a Listit session. The server
  /// verifies the token with Facebook and returns our own JWT + user, so the
  /// response shape matches [login]/[register].
  Future<AuthResult> facebookLogin({required String accessToken}) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.facebookLogin),
          headers: _headers,
          body: jsonEncode({'access_token': accessToken}),
        )
        .timeout(_timeout);
    return _authResult(_unwrap(res));
  }

  // --- Verification --------------------------------------------------------

  /// Send (or resend) a verification code. [type] 1 = email, 2 = phone. For
  /// phone the seller's chosen [number]/[flag]/[countryCode] ride along so the
  /// server stores them and texts the code there.
  Future<void> sendVerificationCode({
    required int type,
    required int userId,
    String? number,
    String? flag,
    String? countryCode,
  }) async {
    final body = <String, dynamic>{'type': type, 'user_id': userId};
    if (type == 2) {
      body['number'] = number;
      body['flag'] = flag;
      body['country_code'] = countryCode;
    }
    final res = await _client
        .post(Uri.parse(ApiConfig.sendOtp),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _unwrap(res);
  }

  /// Confirm the 6-digit code. [type] 1 = email, 2 = phone.
  Future<void> verifyCode({
    required int type,
    required String otp,
    required int userId,
    String? number,
    String? flag,
    String? countryCode,
  }) async {
    final body = <String, dynamic>{
      'type': type,
      'otp': otp,
      'user_id': userId,
    };
    if (type == 2) {
      body['number'] = number;
      body['flag'] = flag;
      body['country_code'] = countryCode;
    }
    final res = await _client
        .post(Uri.parse(ApiConfig.verifyOtp),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _unwrap(res);
  }

  /// Reveal a dealer's main contact number, e.g. `{number, flag}`. Returns null
  /// if the backend has nothing on file.
  Future<Map<String, String>?> revealDealerPhone(int userId) async {
    final res = await _client
        .post(Uri.parse(ApiConfig.dealerPhone),
            headers: _headers, body: jsonEncode({'user_id': userId}))
        .timeout(_timeout);
    final data = _unwrap(res);
    final info = data['user_info'];
    if (info is! Map) return null;
    final number = (info['number'] ?? '').toString();
    if (number.isEmpty) return null;
    return {'number': number, 'flag': (info['flag'] ?? '44').toString()};
  }

  /// The signed-in user's own profile (auth required).
  Future<AppUser> fetchProfile() async {
    final res =
        await _client.get(Uri.parse(ApiConfig.profile), headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    final info = data['user_info'] ?? data['result'] ?? data;
    return AppUser.fromJson(info as Map<String, dynamic>);
  }

  // --- Saved ads -----------------------------------------------------------

  Future<void> saveAd({required int userId, required int adId}) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.saveAd),
          headers: _headers,
          body: jsonEncode({'user_id': userId, 'ad_id': adId}),
        )
        .timeout(_timeout);
    _unwrap(res);
  }

  Future<void> unsaveAd({required int userId, required int adId}) async {
    final req = http.Request('DELETE', Uri.parse(ApiConfig.saveAd))
      ..headers.addAll(_headers)
      ..body = jsonEncode({'user_id': userId, 'ad_id': adId});
    final streamed = await _client.send(req).timeout(_timeout);
    _unwrap(await http.Response.fromStream(streamed));
  }

  Future<List<Ad>> listSavedAds({required int userId, int page = 1}) async {
    final uri = Uri.parse(ApiConfig.saveAd)
        .replace(queryParameters: {'user_id': '$userId', 'page': '$page'});
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    return (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Ad.fromJson)
        .toList();
  }

  // --- Selling (place an ad) -----------------------------------------------

  /// The whole category tree as a flat list (top-level + every child), so the
  /// Sell flow can drill down section -> subsection until it reaches a leaf.
  Future<List<Category>> fetchAllCategories() async {
    final res = await _client
        .get(Uri.parse(ApiConfig.categories))
        .timeout(_timeout);
    final data = _unwrap(res);
    return (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Category.fromJson)
        .where((c) => c.name.isNotEmpty)
        .toList();
  }

  /// Listing plans available to the signed-in user (Lite is the free tier).
  Future<List<Plan>> fetchPlans() async {
    final res = await _client
        .get(Uri.parse(ApiConfig.plans), headers: _headers)
        .timeout(_timeout);
    final data = _unwrap(res);
    return (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Plan.fromJson)
        .toList();
  }

  /// Upload one photo to Cloudinary via the backend and return its hosted URL.
  /// Mirrors the website's dealer form: multipart field `image`, URL comes back
  /// in `data.file.path`.
  Future<String> uploadPhoto(File file) async {
    final req = http.MultipartFile.fromBytes(
      'image',
      await file.readAsBytes(),
      filename: file.path.split('/').last,
    );
    final request = http.MultipartRequest('POST', Uri.parse(ApiConfig.uploadImage))
      ..files.add(req);
    final token = _getToken?.call();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final streamed = await _client.send(request).timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    // This endpoint returns { error } on failure rather than the envelope, so
    // surface that message directly if present.
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Photo upload failed (${res.statusCode}).';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['error'] != null) msg = b['error'].toString();
      } catch (_) {}
      throw ApiException(msg);
    }
    final data = _unwrap(res);
    final file0 = data['file'];
    final url = file0 is Map ? (file0['path'] ?? file0['filename'] ?? '') : '';
    if (url.toString().isEmpty) throw ApiException('Photo upload failed.');
    return url.toString();
  }

  /// Publish a new ad. [payload] is the full body the backend expects (built by
  /// the Sell flow). Returns the raw data map (contains the new ad id).
  Future<Map<String, dynamic>> createAd(Map<String, dynamic> payload) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.createAd),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    return _unwrap(res);
  }

  void dispose() => _client.close();
}
