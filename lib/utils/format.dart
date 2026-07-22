import 'package:intl/intl.dart';
import '../models/ad.dart';

/// Display helpers shared across the app. Prices on the Isle of Man are in
/// pounds sterling.
class Format {
  Format._();

  static final NumberFormat _gbp = NumberFormat.currency(
    locale: 'en_GB',
    symbol: '£',
    decimalDigits: 0,
  );

  static String price(Ad ad) {
    if (ad.isFree) return 'Free';
    return _gbp.format(ad.price);
  }

  static String? oldPrice(Ad ad) {
    if (!ad.hasDiscount) return null;
    return _gbp.format(ad.oldPrice);
  }

  /// "2h ago", "3d ago", "just now" - lightweight relative time without a
  /// dependency on a heavy timeago package.
  static String timeAgo(DateTime? when, {DateTime? now}) {
    if (when == null) return '';
    final ref = now ?? DateTime.now();
    final diff = ref.difference(when);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}
