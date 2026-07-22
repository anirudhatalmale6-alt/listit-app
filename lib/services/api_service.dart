import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/ad.dart';
import '../models/category.dart';

/// Result of a search page - the ads plus the total so the UI can show
/// "718 in Cars & Motors" and know when to stop paginating.
class SearchResult {
  final List<Ad> ads;
  final int total;
  const SearchResult(this.ads, this.total);
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
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 20);

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
          headers: const {'Content-Type': 'application/json'},
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

  void dispose() => _client.close();
}
