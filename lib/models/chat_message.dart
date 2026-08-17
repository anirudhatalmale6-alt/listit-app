/// A single message inside a chat thread. Offers ride the same table as plain
/// messages (the backend just prefixes the text, e.g. "Offer: £120 (asking
/// £150)"), so we sniff the text to render them as offer bubbles.
class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String text;
  final DateTime? sentAt;
  final int messageType;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    required this.messageType,
  });

  /// True for the system-style offer lines the backend writes into the thread.
  bool get isOffer {
    final t = text.toLowerCase();
    return t.startsWith('offer:') ||
        t.startsWith('offer accepted') ||
        t.startsWith('offer declined');
  }

  bool get isOfferAccepted => text.toLowerCase().startsWith('offer accepted');
  bool get isOfferDeclined => text.toLowerCase().startsWith('offer declined');

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    return ChatMessage(
      id: _int(j['id']),
      conversationId: _int(j['conversation_id']),
      senderId: _int(j['sender_id']),
      text: (j['message_text'] ?? '').toString(),
      sentAt: DateTime.tryParse((j['sent_at'] ?? j['created_at'] ?? '').toString()),
      messageType: _int(j['message_type']),
    );
  }
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
