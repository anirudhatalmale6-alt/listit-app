import 'dart:convert';
import '../config/api_config.dart';

/// One chat thread between a buyer and a seller about a single ad. Backs the
/// Messages tab list. The backend joins in both parties and the ad, so a row
/// carries everything the list needs without a second call.
class Conversation {
  final int id;
  final int adId;
  final int buyerId;
  final int sellerId;
  final String lastMessageText;
  final DateTime? lastMessageAt;
  final int buyerUnread;
  final int sellerUnread;
  final int lastMessageBy;

  final int otherPartyIdForBuyer; // convenience filled by fromJson
  final ConvParty buyer;
  final ConvParty seller;
  final String adTitle;
  final double adPrice;
  final String? adImage;

  const Conversation({
    required this.id,
    required this.adId,
    required this.buyerId,
    required this.sellerId,
    required this.lastMessageText,
    required this.lastMessageAt,
    required this.buyerUnread,
    required this.sellerUnread,
    required this.lastMessageBy,
    required this.otherPartyIdForBuyer,
    required this.buyer,
    required this.seller,
    required this.adTitle,
    required this.adPrice,
    required this.adImage,
  });

  /// The person on the far side of this thread, given who is looking.
  ConvParty other(int me) => me == buyerId ? seller : buyer;

  /// Am I the seller on this ad? (drives "you'll receive offers" wording).
  bool viewerIsSeller(int me) => me == sellerId;

  /// Unread messages waiting for the given user.
  int unreadFor(int me) => me == buyerId ? buyerUnread : sellerUnread;

  factory Conversation.fromJson(Map<String, dynamic> j) {
    return Conversation(
      id: _int(j['id']),
      adId: _int(j['ad_id']),
      buyerId: _int(j['buyer_id']),
      sellerId: _int(j['seller_id']),
      lastMessageText: (j['last_message_text'] ?? '').toString(),
      lastMessageAt: DateTime.tryParse((j['last_message_at'] ?? '').toString()),
      buyerUnread: _int(j['buyer_unread_count']),
      sellerUnread: _int(j['seller_unread_count']),
      lastMessageBy: _int(j['last_message_by']),
      otherPartyIdForBuyer: _int(j['seller_id']),
      buyer: ConvParty.fromJson(j['buyer']),
      seller: ConvParty.fromJson(j['seller']),
      adTitle: (j['ad']?['title'] ?? j['ad_title'] ?? '').toString(),
      adPrice: _double(j['ad']?['price'] ?? j['ad_price']),
      adImage: _firstImage(j['ad']?['images'] ?? j['ad_images']),
    );
  }
}

/// A lightweight buyer/seller summary carried on a conversation row.
class ConvParty {
  final int id;
  final String name;
  final String? avatar;

  const ConvParty({required this.id, required this.name, this.avatar});

  String get displayName => name.trim().isEmpty ? 'Listit user' : name.trim();

  String get initials {
    final parts = displayName.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory ConvParty.fromJson(dynamic j) {
    if (j is! Map) return const ConvParty(id: 0, name: '');
    final img = (j['image'] ?? j['logo'] ?? '').toString();
    return ConvParty(
      id: _int(j['id']),
      name: (j['name'] ?? '').toString(),
      avatar: img.isEmpty ? null : ApiConfig.resolveImage(img),
    );
  }
}

int _int(dynamic v) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double _double(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String? _firstImage(dynamic value) {
  if (value == null) return null;
  List<dynamic> list;
  if (value is List) {
    list = value;
  } else if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      list = decoded is List ? decoded : [decoded];
    } catch (_) {
      list = [value];
    }
  } else {
    return null;
  }
  if (list.isEmpty) return null;
  final resolved = ApiConfig.resolveImage(list.first?.toString());
  return resolved.isEmpty ? null : resolved;
}
