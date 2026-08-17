/// The draft Larry returns after looking at a seller's photo. Everything is a
/// suggestion the seller can edit before posting.
class ScanResult {
  final bool isItem;
  final String title;
  final String description;
  final int? price; // rough second-hand price in whole £, or null if unsure
  final String priceNote;
  final String category;
  final String confidence;

  const ScanResult({
    required this.isItem,
    required this.title,
    required this.description,
    required this.price,
    required this.priceNote,
    required this.category,
    required this.confidence,
  });

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.round();
    return int.tryParse('$v');
  }

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        isItem: j['is_item'] != false,
        title: (j['title'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        price: _asIntOrNull(j['price']),
        priceNote: (j['price_note'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        confidence: (j['confidence'] ?? '').toString(),
      );

  /// True when there's nothing useful to prefill (not a sellable item / blank).
  bool get isEmpty => !isItem || (title.trim().isEmpty && description.trim().isEmpty);
}
