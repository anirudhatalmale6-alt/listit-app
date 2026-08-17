import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../config/api_config.dart';
import '../models/ad.dart';
import '../models/ad_attribute.dart';
import '../models/app_user.dart';
import '../models/category.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/featured_dealer.dart';
import '../models/plan.dart';
import '../models/saved_search.dart';
import '../models/scan_result.dart';
import '../models/vehicle_facets.dart';

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

/// The full contents of one chat thread: every message plus the ad and both
/// parties, exactly as the `/message` endpoint returns them together.
class MessageThread {
  final List<ChatMessage> messages;
  final Ad? ad;
  final ConvParty? buyer;
  final ConvParty? seller;
  const MessageThread({
    required this.messages,
    this.ad,
    this.buyer,
    this.seller,
  });
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
  ApiService({
    http.Client? client,
    String? Function()? getToken,
    void Function()? onUnauthorized,
  }) : _client = client ?? http.Client() {
    _getToken = getToken;
    _onUnauthorized = onUnauthorized;
  }

  final http.Client _client;

  /// Supplies the current JWT (from AuthService) so gated calls can attach the
  /// Authorization header without this client owning session state.
  String? Function()? _getToken;

  /// Invoked when a gated call returns 401, so the session can be cleared and
  /// the user prompted to sign in again (an expired/invalid token).
  void Function()? _onUnauthorized;

  static const Duration _timeout = Duration(seconds: 20);

  Map<String, String> get _headers {
    final h = {'Content-Type': 'application/json'};
    final token = _getToken?.call();
    if (token != null && token.isNotEmpty) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Map<String, dynamic> _unwrap(http.Response res) {
    // Parse the body first: the API returns a helpful `message` (e.g. "Invalid
    // Password") even on 4xx, so we surface that instead of a bare status code.
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {/* non-JSON error page */}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      // 401 = the token is missing/expired/invalid. Clear the session so the
      // app prompts a fresh sign-in instead of silently failing every call.
      if (res.statusCode == 401) _onUnauthorized?.call();
      final msg = body?['message']?.toString();
      throw ApiException((msg != null && msg.isNotEmpty)
          ? msg
          : 'Something went wrong (${res.statusCode}). Please try again.');
    }
    if (body == null) {
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

  /// Site settings the website also consumes (social links, banner images,
  /// contact details), flattened from the `[{col, value}]` rows into a plain
  /// `col -> value` map. Used for the Social media screen and the home banner
  /// so both mirror whatever is configured on the website.
  Future<Map<String, String>> fetchSiteSettings() async {
    final res = await _client
        .get(Uri.parse(ApiConfig.settings), headers: _headers)
        .timeout(_timeout);
    final data = _unwrap(res);
    final rows = (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>();
    final map = <String, String>{};
    for (final row in rows) {
      final col = row['col']?.toString();
      final value = row['value']?.toString();
      if (col != null && col.isNotEmpty && value != null) {
        map[col] = value;
      }
    }
    return map;
  }

  /// One page of the filtered feed. `category` is a slug ("cars-and-motors")
  /// or "all" for everything. Extra [filters] (keyword, price range, ...) are
  /// merged into the POST body and passed straight through to the backend.
  Future<SearchResult> search({
    int? categoryId,
    bool isVehicle = false,
    int page = 1,
    int limit = 20,
    Map<String, dynamic> filters = const {},
  }) async {
    // The backend filters on `categories` (the numeric id) + `status`; the old
    // `category` slug it silently ignores, which meant every category showed the
    // whole marketplace. status:1 = Listed, so we only ever surface live ads -
    // this also makes our counts line up with the website exactly.
    final body = <String, dynamic>{
      'status': 1,
      'page': page,
      'limit': limit,
      if (categoryId != null) 'categories': categoryId.toString(),
      if (categoryId != null) 'is_vehicle': isVehicle ? 1 : 0,
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

  /// The signed-in user's own ads across every status (live, sold, pending),
  /// newest first - backs the "My listings" screen. Omitting `status` returns
  /// all of a user's ads rather than just the live ones.
  Future<SearchResult> listMyAds({required int userId, int page = 1, int limit = 20}) async {
    final body = <String, dynamic>{
      'user_id': userId,
      'page': page,
      'limit': limit,
      'sort_by': 'created_at',
      'sort_order': 'DESC',
    };
    final res = await _client
        .post(Uri.parse(ApiConfig.search),
            headers: _headers, body: jsonEncode(body))
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

  /// Exchange a Google idToken (from the native sign-in) for a Listit session.
  /// The server verifies the token with Google before issuing our JWT.
  Future<AuthResult> googleLogin({required String idToken}) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.googleLogin),
          headers: _headers,
          body: jsonEncode({'id_token': idToken}),
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

  /// Onboarding / edit-profile save: profile photo URL and/or home town.
  /// Either or both — the backend updates only what's provided.
  Future<void> updateBasicProfile({String? imageUrl, String? location}) async {
    final body = <String, dynamic>{};
    if (imageUrl != null && imageUrl.isNotEmpty) body['image'] = imageUrl;
    if (location != null && location.isNotEmpty) body['location'] = location;
    final res = await _client
        .patch(Uri.parse(ApiConfig.updateBasicProfile),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _unwrap(res);
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

  /// Report an ad for review. Mirrors the website's report form; requires a
  /// signed-in session (the backend gates it behind auth).
  Future<void> reportAd({
    required int adId,
    required int ownerId,
    required int userId,
    required String name,
    required String email,
    required String reason,
    required String comment,
  }) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.reportAd),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'email': email,
            'reason': reason,
            'comment': comment,
            'ad_id': adId,
            'user_id': userId,
            'owner_id': ownerId,
            'support_email': ApiConfig.supportEmail,
          }),
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

  /// The category-specific attributes (Bedrooms, Storage, ...) for [categoryId].
  /// Drives the dynamic filters and Sell-form fields. Returns [] on any error
  /// so callers can fall back to the standard filters.
  Future<List<AdAttribute>> fetchAttributes(int categoryId) async {
    try {
      final uri = Uri.parse(ApiConfig.attributes)
          .replace(queryParameters: {'category_id': '$categoryId'});
      final res = await _client.get(uri, headers: _headers).timeout(_timeout);
      final data = _unwrap(res);
      return (data['result'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdAttribute.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The island's vehicle facets - distinct makes, fuel types, body types and
  /// colours with live counts - for the car-search make list and filters.
  Future<VehicleFacets> fetchVehicleFacets() async {
    final res = await _client
        .get(Uri.parse(ApiConfig.popularSearches))
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return const VehicleFacets();
    }
    // This endpoint returns the facet rows as a bare list under `data` (not the
    // usual { result } map), so read the body directly rather than via _unwrap.
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return const VehicleFacets();
    final rows = decoded['data'];
    if (rows is List) return VehicleFacets.fromRows(rows);
    // The `_new` variant nests the car facets under data.cars.
    if (rows is Map && rows['cars'] is List) {
      return VehicleFacets.fromRows(rows['cars'] as List);
    }
    return const VehicleFacets();
  }

  /// Featured dealers / estate agents for a section (`motors` or `property`).
  /// Only businesses with live, paid (featured) stock come back.
  Future<List<FeaturedDealer>> fetchFeaturedDealers({
    required String sector,
  }) async {
    final res = await _client
        .get(Uri.parse(ApiConfig.featuredDealers(sector)))
        .timeout(_timeout);
    final data = _unwrap(res);
    return (data['dealers'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(FeaturedDealer.fromJson)
        .toList();
  }

  /// Listing plans available to the signed-in user (Lite is the free tier).
  /// Plans available for [categoryId] (the leaf category), matching the
  /// website's `/user/plan?category=<id>`. The API returns them priciest-first;
  /// the website reverses so the free/Lite tier leads, so we do the same.
  Future<List<Plan>> fetchPlans([int? categoryId]) async {
    final uri = Uri.parse(ApiConfig.plans).replace(
      queryParameters:
          categoryId != null ? {'category': categoryId.toString()} : null,
    );
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    return (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Plan.fromJson)
        .toList()
        .reversed
        .toList();
  }

  /// Upload one photo to Cloudinary via the backend and return its hosted URL.
  /// Mirrors the website's dealer form: multipart field `image`, URL comes back
  /// in `data.file.path`.
  Future<String> uploadPhoto(File file) async {
    // The server only accepts real image mime types (jpeg/png/gif/webp). Without
    // an explicit content-type the part defaults to application/octet-stream and
    // the upload is rejected, so tag it from the file extension.
    final ext = file.path.split('.').last.toLowerCase();
    final subtype = ext == 'png'
        ? 'png'
        : ext == 'gif'
            ? 'gif'
            : ext == 'webp'
                ? 'webp'
                : 'jpeg';
    final req = http.MultipartFile.fromBytes(
      'image',
      await file.readAsBytes(),
      filename: file.path.split('/').last,
      contentType: MediaType('image', subtype),
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

  /// Larry's photo scan. Send an already-uploaded image URL and get back a
  /// drafted title / description / rough price. Returns null on any failure so
  /// the caller can quietly fall back to manual entry (mirrors [lookupVehicle]).
  /// Uses a longer timeout since the vision model can take a few seconds.
  Future<ScanResult?> scanItem(String imageUrl) async {
    try {
      final res = await _client
          .post(
            Uri.parse(ApiConfig.scanItem),
            headers: _headers,
            body: jsonEncode({'image_url': imageUrl}),
          )
          .timeout(const Duration(seconds: 45));
      final data = _unwrap(res);
      return ScanResult.fromJson(data);
    } catch (_) {
      return null;
    }
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

  /// Look up a vehicle by its registration for the Sell form's "Find" button.
  /// Returns the details map (make, model, year, fuel_type, colour, ...) with
  /// the same snake_case keys the ad stores, or null if nothing was found.
  Future<Map<String, dynamic>?> lookupVehicle(String registration) async {
    // Mirror the website: any failure (not found, network, auth blip) just
    // means "no match - fill the details in manually", never a hard error.
    try {
      final uri = Uri.parse(ApiConfig.vehicleLookup).replace(
        queryParameters: {'registration_number': registration.trim()},
      );
      final res = await _client.get(uri, headers: _headers).timeout(_timeout);
      final data = _unwrap(res);
      final result = data['result'];
      // The endpoint returns a list of matches; take the first.
      if (result is List && result.isNotEmpty && result.first is Map) {
        return (result.first as Map).cast<String, dynamic>();
      }
      if (result is Map && result.isNotEmpty) {
        return result.cast<String, dynamic>();
      }
    } catch (_) {/* fall through to null - user fills in manually */}
    return null;
  }

  /// Verify vehicle ownership from the log book (V5C/VRC) number. Returns true
  /// when the reg + log book match - which earns the Greenlight badge.
  Future<bool> verifyVehicleOwnership(String registration, String vrc) async {
    final uri = Uri.parse(ApiConfig.verifyOwnership).replace(
      queryParameters: {
        'registration_number': registration.trim(),
        'vrc': vrc.trim(),
      },
    );
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    final result = data['result'];
    if (result is List) return result.isNotEmpty;
    if (result is Map) return result.isNotEmpty;
    if (result is bool) return result;
    return false;
  }

  // --- Messaging + offers --------------------------------------------------

  /// Every conversation the user takes part in (as buyer or seller), newest
  /// activity first. The backend joins in both parties and the ad.
  Future<List<Conversation>> listConversations({
    required int userId,
    int page = 1,
    int limit = 50,
  }) async {
    final uri = Uri.parse(ApiConfig.conversation).replace(queryParameters: {
      'user_id': '$userId',
      'offset': '$page', // the endpoint treats `offset` as the page number
      'limit': '$limit',
      'sort_by': 'last_message_at',
      'sort_order': 'DESC',
    });
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    return (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Conversation.fromJson)
        .toList();
  }

  /// Find the existing thread for this ad between me and the seller, if any,
  /// so we never spin up a duplicate conversation.
  Future<Conversation?> findConversation({
    required int userId,
    required int adId,
    required int sellerId,
  }) async {
    final uri = Uri.parse(ApiConfig.conversation).replace(queryParameters: {
      'user_id': '$userId',
      'ad_id': '$adId',
      'limit': '20',
    });
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    final rows = (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Conversation.fromJson);
    for (final c in rows) {
      if (c.adId == adId &&
          ((c.buyerId == userId && c.sellerId == sellerId) ||
              (c.sellerId == userId && c.buyerId == sellerId))) {
        return c;
      }
    }
    return null;
  }

  /// Open a brand-new thread with the seller and post the first message.
  /// Returns the new conversation id.
  Future<int> startConversation({
    required int adId,
    required int buyerId,
    required int sellerId,
    required String text,
  }) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.conversation),
          headers: _headers,
          body: jsonEncode({
            'ad_id': adId,
            'buyer_id': buyerId,
            'seller_id': sellerId,
            'last_message_text': text,
            'buyer_unread_count': 0,
            'seller_unread_count': 1,
            'last_message_by': buyerId,
          }),
        )
        .timeout(_timeout);
    final data = _unwrap(res);
    return data['conversation_id'] is num
        ? (data['conversation_id'] as num).toInt()
        : int.tryParse('${data['conversation_id']}') ?? 0;
  }

  /// Post a reply into an existing thread.
  Future<void> sendChatMessage({
    required int conversationId,
    required int senderId,
    required String text,
  }) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.message),
          headers: _headers,
          body: jsonEncode({
            'conversation_id': conversationId,
            'sender_id': senderId,
            'message_text': text,
          }),
        )
        .timeout(_timeout);
    _unwrap(res);
  }

  /// Load a thread's messages (this also clears the caller's unread count
  /// server-side, so the badge drops as soon as they open the chat).
  Future<MessageThread> listMessages({
    required int conversationId,
    required int userId,
  }) async {
    final uri = Uri.parse(ApiConfig.message).replace(queryParameters: {
      'conversation_id': '$conversationId',
      'user_id': '$userId',
      'sort_by': 'sent_at',
      'sort_order': 'ASC',
    });
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    final msgs = (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
    Ad? ad;
    final adRaw = data['ad'];
    if (adRaw is Map<String, dynamic>) ad = Ad.fromJson(adRaw);
    return MessageThread(
      messages: msgs,
      ad: ad,
      buyer: data['buyer'] is Map ? ConvParty.fromJson(data['buyer']) : null,
      seller: data['seller'] is Map ? ConvParty.fromJson(data['seller']) : null,
    );
  }

  /// Send a price offer. The backend creates/reuses the thread and drops the
  /// offer in as a message, then emails the seller. Returns the conversation
  /// id so we can jump the buyer straight into the chat.
  Future<int> makeOffer({required int adId, required double amount}) async {
    final res = await _client
        .post(
          Uri.parse(ApiConfig.makeOffer),
          headers: _headers,
          body: jsonEncode({'ad_id': adId, 'offer_amount': amount}),
        )
        .timeout(_timeout);
    final data = _unwrap(res);
    return data['conversation_id'] is num
        ? (data['conversation_id'] as num).toInt()
        : int.tryParse('${data['conversation_id']}') ?? 0;
  }

  /// Total unread messages across all the user's threads (drives the tab
  /// badge). Best-effort: returns 0 if the shape is unexpected.
  Future<int> unreadCount({required int userId}) async {
    final uri = Uri.parse(ApiConfig.unreadCount)
        .replace(queryParameters: {'user_id': '$userId'});
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    final c = data['unread_count'] ?? data['count'] ?? data['total'] ?? 0;
    return c is num ? c.toInt() : int.tryParse('$c') ?? 0;
  }

  // --- Saved searches ------------------------------------------------------

  /// Star a search so it can be re-run later. [filters] holds the active
  /// query (keyword/categories/location/price/ad_type); [title] is the label.
  Future<void> saveSearch({
    required int userId,
    required String title,
    required Map<String, dynamic> filters,
  }) async {
    final body = <String, dynamic>{
      'user_id': userId,
      'name': (filters['keyword'] ?? '').toString(),
      'title': title,
      // 1 = instant alerts on new matches (DoneDeal's default when you save a
      // search). The backend rejects 0, and re-run works regardless.
      'alert_category': 1,
      'search_url': '/results',
      'ad_type': filters['ad_type'] ?? '',
      'price_from': filters['price_from'] ?? 0,
      'price_to': filters['price_to'] ?? 0,
      'location': filters['location'] ?? '',
      'category': (filters['categories'] ?? '').toString(),
    };
    final res = await _client
        .post(Uri.parse(ApiConfig.saveSearch),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _unwrap(res);
  }

  Future<List<SavedSearch>> listSavedSearches({required int userId}) async {
    final uri = Uri.parse(ApiConfig.saveSearch)
        .replace(queryParameters: {'user_id': '$userId'});
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    final data = _unwrap(res);
    return (data['result'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SavedSearch.fromJson)
        .toList();
  }

  Future<void> deleteSavedSearch({required int id}) async {
    final req = http.Request('DELETE', Uri.parse('${ApiConfig.saveSearch}/$id'))
      ..headers.addAll(_headers);
    final streamed = await _client.send(req).timeout(_timeout);
    _unwrap(await http.Response.fromStream(streamed));
  }

  void dispose() => _client.close();
}
