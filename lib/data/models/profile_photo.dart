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

/// 预录入界面文案与用户口语 → [ProfilePhotoCategory] 的统一映射。
abstract final class ProfilePhotoCategoryLabels {
  ProfilePhotoCategoryLabels._();

  static const Map<ProfilePhotoCategory, String> displayName = {
    ProfilePhotoCategory.avatar: '老人头像',
    ProfilePhotoCategory.family: '家庭照片',
    ProfilePhotoCategory.memory: '经历照片',
    ProfilePhotoCategory.daily: '日常照片',
    ProfilePhotoCategory.other: '其他照片',
  };

  /// 检索别名（长词在前）；含 DB 字段值 [ProfilePhotoCategory.value]。
  static const Map<ProfilePhotoCategory, List<String>> searchAliases = {
    ProfilePhotoCategory.avatar: [
      'avatar',
      '老人头像',
      '老人照片',
      '老人相片',
      '老人图片',
      '头像照片',
      '本人照片',
    ],
    ProfilePhotoCategory.family: [
      'family',
      '家庭照片',
      '家庭相片',
      '家庭图片',
      '家人照片',
      '亲属照片',
    ],
    ProfilePhotoCategory.memory: [
      'memory',
      '经历照片',
      '经历相片',
      '往事照片',
      '记忆照片',
      '回忆照片',
    ],
    ProfilePhotoCategory.daily: [
      'daily',
      '日常照片',
      '日常相片',
      '生活照片',
      '生活照',
      '生活图片',
    ],
    ProfilePhotoCategory.other: [
      'other',
      '其他照片',
      '其它照片',
    ],
  };

  static String label(ProfilePhotoCategory category) =>
      displayName[category] ?? '照片';

  static List<(String alias, ProfilePhotoCategory category)> _aliasEntries() {
    final out = <(String, ProfilePhotoCategory)>[];
    for (final e in searchAliases.entries) {
      for (final alias in e.value) {
        if (alias.trim().length >= 2) {
          out.add((alias.trim(), e.key));
        }
      }
    }
    out.sort((a, b) => b.$1.length.compareTo(a.$1.length));
    return out;
  }

  /// 从用户整句或关键词解析照片类别（优先匹配更长别名，避免「家庭」误伤「老人家庭」）。
  static ProfilePhotoCategory? categoryFromUserPhrase(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    for (final entry in _aliasEntries()) {
      if (t.contains(entry.$1)) return entry.$2;
    }
    return null;
  }

  /// 关键词是否可能指向某类别（用于 SQL 辅助筛选）。
  static List<ProfilePhotoCategory> categoriesMatchingKeyword(String keyword) {
    final t = keyword.trim();
    if (t.isEmpty) return const [];
    final hits = <ProfilePhotoCategory>{};
    final direct = categoryFromUserPhrase(t);
    if (direct != null) hits.add(direct);
    for (final entry in _aliasEntries()) {
      if (t.contains(entry.$1) || entry.$1.contains(t)) {
        hits.add(entry.$2);
      }
    }
    return hits.toList();
  }

  static bool phraseIndicatesCategory(
    String text,
    ProfilePhotoCategory category,
  ) {
    if (categoryFromUserPhrase(text) == category) return true;
    for (final alias in searchAliases[category] ?? const []) {
      if (alias.length >= 2 && text.contains(alias)) return true;
    }
    return false;
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
