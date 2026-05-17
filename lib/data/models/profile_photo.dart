import 'dart:convert';

enum ProfilePhotoStorageType {
  filePath('file_path'),
  webLocal('web_local');

  const ProfilePhotoStorageType(this.value);

  final String value;

  static ProfilePhotoStorageType fromValue(String? value) {
    return ProfilePhotoStorageType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => ProfilePhotoStorageType.filePath,
    );
  }
}

enum ProfilePhotoCategory {
  avatar('avatar'),
  family('family'),
  memory('memory'),
  daily('daily'),
  other('other');

  const ProfilePhotoCategory(this.value);

  final String value;

  static ProfilePhotoCategory fromValue(String? value) {
    return ProfilePhotoCategory.values.firstWhere(
      (category) => category.value == value,
      orElse: () => ProfilePhotoCategory.other,
    );
  }
}

class ProfilePhotoModel {
  ProfilePhotoModel({
    required this.id,
    required this.ownerUserId,
    required this.filePath,
    this.storageType = ProfilePhotoStorageType.filePath,
    this.category = ProfilePhotoCategory.other,
    this.caption,
    this.photoTime,
    this.location,
    this.peopleInvolved,
    this.familyMemberId,
    this.memoryEventId,
    this.isFavorite = false,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String ownerUserId;
  final String filePath;
  final ProfilePhotoStorageType storageType;
  final ProfilePhotoCategory category;
  final String? caption;
  final String? photoTime;
  final String? location;
  final String? peopleInvolved;
  final int? familyMemberId;
  final int? memoryEventId;
  final bool isFavorite;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'file_path': filePath,
        'storage_type': storageType.value,
        'category': category.value,
        'caption': caption,
        'photo_time': photoTime,
        'location': location,
        'people_involved': peopleInvolved,
        'family_member_id': familyMemberId,
        'memory_event_id': memoryEventId,
        'is_favorite': isFavorite ? 1 : 0,
        'metadata':
            metadata == null ? null : const JsonEncoder().convert(metadata),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static ProfilePhotoModel fromMap(Map<String, dynamic> map) {
    final familyMemberId = map['family_member_id'];
    final memoryEventId = map['memory_event_id'];
    return ProfilePhotoModel(
      id: map['id'] as String,
      ownerUserId: map['owner_user_id'] as String,
      filePath: map['file_path'] as String,
      storageType:
          ProfilePhotoStorageType.fromValue(map['storage_type'] as String?),
      category: ProfilePhotoCategory.fromValue(map['category'] as String?),
      caption: map['caption'] as String?,
      photoTime: map['photo_time'] as String?,
      location: map['location'] as String?,
      peopleInvolved: map['people_involved'] as String?,
      familyMemberId: familyMemberId is num ? familyMemberId.toInt() : null,
      memoryEventId: memoryEventId is num ? memoryEventId.toInt() : null,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
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

  ProfilePhotoModel copyWith({
    String? filePath,
    ProfilePhotoStorageType? storageType,
    ProfilePhotoCategory? category,
    String? caption,
    String? photoTime,
    String? location,
    String? peopleInvolved,
    int? familyMemberId,
    int? memoryEventId,
    bool? isFavorite,
    Map<String, dynamic>? metadata,
  }) {
    return ProfilePhotoModel(
      id: id,
      ownerUserId: ownerUserId,
      filePath: filePath ?? this.filePath,
      storageType: storageType ?? this.storageType,
      category: category ?? this.category,
      caption: caption ?? this.caption,
      photoTime: photoTime ?? this.photoTime,
      location: location ?? this.location,
      peopleInvolved: peopleInvolved ?? this.peopleInvolved,
      familyMemberId: familyMemberId ?? this.familyMemberId,
      memoryEventId: memoryEventId ?? this.memoryEventId,
      isFavorite: isFavorite ?? this.isFavorite,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
