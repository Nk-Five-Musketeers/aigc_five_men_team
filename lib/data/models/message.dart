import 'dart:convert';

class MessageModel {
  MessageModel({
    required this.id,
    required this.conversationId,
    this.userId,
    this.content,
    this.type,
    DateTime? timestamp,
    this.extra,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  final String conversationId;
  final String? userId;
  final String? content;
  final String? type;
  final DateTime timestamp;
  final Map<String, dynamic>? extra;

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'user_id': userId,
        'content': content,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'extra': extra == null ? null : _encode(extra!),
      };

  static MessageModel fromMap(Map<String, dynamic> m) => MessageModel(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        userId: m['user_id'] as String?,
        content: m['content'] as String?,
        type: m['type'] as String?,
        timestamp: DateTime.tryParse(m['timestamp'] as String? ?? '') ??
            DateTime.now(),
        extra: m['extra'] == null ? null : _decode(m['extra'] as String),
      );

  static String _encode(Object o) => const JsonEncoder().convert(o);
  static Map<String, dynamic> _decode(String s) =>
      Map<String, dynamic>.from(const JsonDecoder().convert(s));
}
