class MemoryItem {
  MemoryItem({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.eventTime,
    this.location,
    this.peopleInvolved,
    this.emotion,
    this.photoPaths,
    this.videoPath,
    this.importance = 3,
    this.source = 'AI提取',
    this.verified = false,
    this.usedCount = 0,
    this.lastUsed,
    this.sourceDialog,
  });

  final String id;
  final String? eventTime;
  final String title;
  final String description;
  final String? location;
  final String? peopleInvolved;
  final String? emotion;
  final String? photoPaths;
  final String? videoPath;
  final int importance;
  final String? source;
  final bool verified;
  final int usedCount;
  final DateTime? lastUsed;
  final String? sourceDialog;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get summary => description;

  List<String> get keywords {
    return <String>[
      title,
      if (eventTime != null) eventTime!,
      if (location != null) location!,
      if (peopleInvolved != null) peopleInvolved!,
      if (emotion != null) emotion!,
    ].where((item) => item.trim().isNotEmpty).toList();
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': int.tryParse(id) ?? id,
      'event_time': eventTime,
      'title': title,
      'description': description,
      'location': location,
      'people_involved': peopleInvolved,
      'emotion': emotion,
      'photo_paths': photoPaths,
      'video_path': videoPath,
      'importance': importance,
      'source': source,
      'verified': verified ? 1 : 0,
      'used_count': usedCount,
      'last_used': lastUsed?.toIso8601String(),
      'source_dialog': sourceDialog,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory MemoryItem.fromMap(Map<String, Object?> map) {
    return MemoryItem(
      id: map['id'].toString(),
      eventTime: map['event_time'] as String?,
      title: map['title'] as String,
      description: map['description'] as String,
      location: map['location'] as String?,
      peopleInvolved: map['people_involved'] as String?,
      emotion: map['emotion'] as String?,
      photoPaths: map['photo_paths'] as String?,
      videoPath: map['video_path'] as String?,
      importance: (map['importance'] as num?)?.toInt() ?? 3,
      source: map['source'] as String?,
      verified: ((map['verified'] as num?)?.toInt() ?? 0) == 1,
      usedCount: (map['used_count'] as num?)?.toInt() ?? 0,
      lastUsed: _parseDate(map['last_used']),
      sourceDialog: map['source_dialog'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
