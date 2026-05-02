import 'dart:convert';

class UserModel {
  UserModel(
      {required this.id,
      this.name,
      this.avatarPath,
      this.metadata,
      DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String? name;
  final String? avatarPath;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'avatar_path': avatarPath,
        'metadata': metadata == null ? null : _encode(metadata!),
        'created_at': createdAt.toIso8601String(),
      };

  static UserModel fromMap(Map<String, dynamic> m) => UserModel(
        id: m['id'] as String,
        name: m['name'] as String?,
        avatarPath: m['avatar_path'] as String?,
        metadata:
            m['metadata'] == null ? null : _decode(m['metadata'] as String),
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  static String _encode(Object o) => const JsonEncoder().convert(o);
  static Map<String, dynamic> _decode(String s) =>
      Map<String, dynamic>.from(const JsonDecoder().convert(s));
}
