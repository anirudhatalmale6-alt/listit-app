/// A search the user has starred, as stored server-side (`save_search`). We
/// keep the raw filter columns so re-running one restores the same results.
class SavedSearch {
  final int id;
  final String title;
  final String name;
  final String searchUrl;
  final String category;
  final String location;
  final String? priceFrom;
  final String? priceTo;
  final int? adType;

  const SavedSearch({
    required this.id,
    required this.title,
    required this.name,
    required this.searchUrl,
    required this.category,
    required this.location,
    this.priceFrom,
    this.priceTo,
    this.adType,
  });

  /// The keyword this search was for (stored in `name`), if any.
  String get keyword => name.trim();

  /// Rebuild the filter map to hand back to a results screen.
  Map<String, dynamic> toFilters() {
    final m = <String, dynamic>{};
    if (keyword.isNotEmpty) m['keyword'] = keyword;
    if (category.isNotEmpty) m['categories'] = category;
    if (location.isNotEmpty) m['location'] = location;
    if ((priceFrom ?? '').isNotEmpty && priceFrom != '0') {
      m['price_from'] = priceFrom;
    }
    if ((priceTo ?? '').isNotEmpty && priceTo != '0') m['price_to'] = priceTo;
    if (adType != null && adType != 0) m['ad_type'] = adType;
    return m;
  }

  factory SavedSearch.fromJson(Map<String, dynamic> j) {
    int? ai(dynamic v) {
      final n = int.tryParse('${v ?? ''}');
      return (n == null || n == 0) ? null : n;
    }

    return SavedSearch(
      id: int.tryParse('${j['id'] ?? ''}') ?? 0,
      title: (j['title'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      searchUrl: (j['search_url'] ?? '').toString(),
      category: (j['category'] ?? '').toString(),
      location: (j['location'] ?? '').toString(),
      priceFrom: (j['price_from'] ?? '').toString(),
      priceTo: (j['price_to'] ?? '').toString(),
      adType: ai(j['ad_type']),
    );
  }
}
