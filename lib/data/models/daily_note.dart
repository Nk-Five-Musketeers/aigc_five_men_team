class DailyNote {
  DailyNote({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.breakfast,
    this.lunch,
    this.dinner,
    this.activities,
    this.peopleMet,
    this.placesWent,
    this.mood,
    this.rawExtract,
    this.sourceDialog,
  });

  final String id;
  final String date;
  final String? breakfast;
  final String? lunch;
  final String? dinner;
  final String? activities;
  final String? peopleMet;
  final String? placesWent;
  final String? mood;
  final String? rawExtract;
  final String? sourceDialog;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get title {
    if (_hasValue(lunch) || _hasValue(breakfast) || _hasValue(dinner)) {
      return '今日饮食记录';
    }
    if (_hasValue(activities) || _hasValue(placesWent) || _hasValue(peopleMet)) {
      return '今日活动记录';
    }
    if (_hasValue(mood)) return '今日心情记录';
    return '今日生活记录';
  }

  String get description {
    final parts = <String>[
      if (_hasValue(breakfast)) '早餐：$breakfast',
      if (_hasValue(lunch)) '午餐：$lunch',
      if (_hasValue(dinner)) '晚餐：$dinner',
      if (_hasValue(activities)) '活动：$activities',
      if (_hasValue(peopleMet)) '见到：$peopleMet',
      if (_hasValue(placesWent)) '去了：$placesWent',
      if (_hasValue(mood)) '心情：$mood',
      if (_hasValue(rawExtract)) rawExtract!,
    ];
    return parts.isEmpty ? '记录了一条新的生活信息。' : parts.join('；');
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': int.tryParse(id) ?? id,
      'date': date,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'activities': activities,
      'people_met': peopleMet,
      'places_went': placesWent,
      'mood': mood,
      'raw_extract': rawExtract,
      'source_dialog': sourceDialog,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DailyNote.fromMap(Map<String, Object?> map) {
    return DailyNote(
      id: map['id'].toString(),
      date: map['date'] as String,
      breakfast: map['breakfast'] as String?,
      lunch: map['lunch'] as String?,
      dinner: map['dinner'] as String?,
      activities: map['activities'] as String?,
      peopleMet: map['people_met'] as String?,
      placesWent: map['places_went'] as String?,
      mood: map['mood'] as String?,
      rawExtract: map['raw_extract'] as String?,
      sourceDialog: map['source_dialog'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  bool _hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
