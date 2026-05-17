class ConversationModel {
  ConversationModel({required this.id, this.title, DateTime? createdAt, this.lastMessageId})
      : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String? title;
  final DateTime createdAt;
  final String? lastMessageId;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        'last_message_id': lastMessageId,
      };

  static ConversationModel fromMap(Map<String, dynamic> m) => ConversationModel(
        id: m['id'] as String,
        title: m['title'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        lastMessageId: m['last_message_id'] as String?,
      );
}
