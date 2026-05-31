import 'dart:convert';

class LifeEventModel {
  LifeEventModel({
    required this.id,
    required this.ownerUserId,
    this.eventTime,
    this.title,
    this.description,
    this.location,
    this.peopleInvolved,
    this.emotion,
    this.photoPaths,
    this.videoPaths,
    this.importance,
    this.source,
    this.verified = false,
    this.usedCount = 0,
    DateTime? lastUsed,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : lastUsed = lastUsed,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String ownerUserId;
  final String? eventTime;
  final String? title;
  final String? description;
  final String? location;
  final String? peopleInvolved;
  final String? emotion;
  final List<String>? photoPaths;
  final List<String>? videoPaths;
  final int? importance;
  final String? source;
  final bool verified;
  final int usedCount;
  final DateTime? lastUsed;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'event_time': eventTime,
        'title': title,
        'description': description,
        'location': location,
        'people_involved': peopleInvolved,
        'emotion': emotion,
        'photo_paths': photoPaths == null ? null : json.encode(photoPaths),
        'video_paths': videoPaths == null ? null : json.encode(videoPaths),
        'importance': importance,
        'source': source,
        'verified': verified ? 1 : 0,
        'used_count': usedCount,
        'last_used': lastUsed?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static LifeEventModel fromMap(Map<String, dynamic> m) => LifeEventModel(
        id: m['id'] as String,
        ownerUserId: m['owner_user_id'] as String,
        eventTime: m['event_time'] as String?,
        title: m['title'] as String?,
        description: m['description'] as String?,
        location: m['location'] as String?,
        peopleInvolved: m['people_involved'] as String?,
        emotion: m['emotion'] as String?,
        photoPaths: m['photo_paths'] == null ? null : List<String>.from(json.decode(m['photo_paths'] as String)),
        videoPaths: m['video_paths'] == null ? null : List<String>.from(json.decode(m['video_paths'] as String)),
        importance: (m['importance'] as num?)?.toInt(),
        source: m['source'] as String?,
        verified: (m['verified'] as int? ?? 0) == 1,
        usedCount: (m['used_count'] as int?) ?? 0,
        lastUsed: DateTime.tryParse(m['last_used'] as String? ?? ''),
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  LifeEventModel copyWith({
    String? title,
    String? description,
    String? location,
    List<String>? photoPaths,
    List<String>? videoPaths,
    int? importance,
    bool? verified,
    int? usedCount,
  }) =>
      LifeEventModel(
        id: id,
        ownerUserId: ownerUserId,
        eventTime: eventTime,
        title: title ?? this.title,
        description: description ?? this.description,
        location: location ?? this.location,
        peopleInvolved: peopleInvolved ?? this.peopleInvolved,
        emotion: emotion ?? this.emotion,
        photoPaths: photoPaths ?? this.photoPaths,
        videoPaths: videoPaths ?? this.videoPaths,
        importance: importance ?? this.importance,
        source: source ?? this.source,
        verified: verified ?? this.verified,
        usedCount: usedCount ?? this.usedCount,
        lastUsed: lastUsed,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
