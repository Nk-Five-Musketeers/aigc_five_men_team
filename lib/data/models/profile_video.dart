import 'dart:convert';

enum ProfileVideoCategory {
  family('family'),
  memory('memory'),
  daily('daily'),
  other('other');

  const ProfileVideoCategory(this.value);
  final String value;

  static ProfileVideoCategory fromValue(String? value) {
    return ProfileVideoCategory.values.firstWhere(
      (c) => c.value == value,
      orElse: () => ProfileVideoCategory.other,
    );
  }
}

class ProfileVideoModel {
  ProfileVideoModel({
    required this.id,
    required this.ownerUserId,
    required this.filePath,
    this.category = ProfileVideoCategory.memory,
    this.caption,
    this.videoTime,
    this.location,
    this.peopleInvolved,
    this.familyMemberId,
    this.memoryEventId,
    this.isFavorite = false,
    this.messageId,
    this.mime,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String ownerUserId;
  final String filePath;
  final ProfileVideoCategory category;
  final String? caption;
  final String? videoTime;
  final String? location;
  final String? peopleInvolved;
  final int? familyMemberId;
  final int? memoryEventId;
  final bool isFavorite;
  final String? messageId;
  final String? mime;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'file_path': filePath,
        'category': category.value,
        'caption': caption,
        'video_time': videoTime,
        'location': location,
        'people_involved': peopleInvolved,
        'family_member_id': familyMemberId,
        'memory_event_id': memoryEventId,
        'is_favorite': isFavorite ? 1 : 0,
        'message_id': messageId,
        'mime': mime,
        'metadata':
            metadata == null ? null : const JsonEncoder().convert(metadata),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static ProfileVideoModel fromMap(Map<String, dynamic> map) {
    final familyMemberId = map['family_member_id'];
    final memoryEventId = map['memory_event_id'];
    return ProfileVideoModel(
      id: map['id'] as String,
      ownerUserId: map['owner_user_id'] as String,
      filePath: map['file_path'] as String,
      category: ProfileVideoCategory.fromValue(map['category'] as String?),
      caption: map['caption'] as String?,
      videoTime: map['video_time'] as String?,
      location: map['location'] as String?,
      peopleInvolved: map['people_involved'] as String?,
      familyMemberId: familyMemberId is num ? familyMemberId.toInt() : null,
      memoryEventId: memoryEventId is num ? memoryEventId.toInt() : null,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      messageId: map['message_id'] as String?,
      mime: map['mime'] as String?,
      metadata: map['metadata'] == null
          ? null
          : Map<String, dynamic>.from(
              const JsonDecoder().convert(map['metadata'] as String),
            ),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
