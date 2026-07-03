import 'dart:convert';

class DailyRecordModel {
  DailyRecordModel({
    required this.id,
    required this.ownerUserId,
    this.date,
    this.breakfast,
    this.lunch,
    this.dinner,
    this.activities,
    this.peopleMet,
    this.placesWent,
    this.mood,
    this.rawExtract,
    this.sourceDialogId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String ownerUserId;
  final String? date;
  final String? breakfast;
  final String? lunch;
  final String? dinner;
  final String? activities;
  final String? peopleMet;
  final String? placesWent;
  final String? mood;
  final Map<String, dynamic>? rawExtract;
  final String? sourceDialogId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'date': date,
        'breakfast': breakfast,
        'lunch': lunch,
        'dinner': dinner,
        'activities': activities,
        'people_met': peopleMet,
        'places_went': placesWent,
        'mood': mood,
        'raw_extract': rawExtract == null ? null : json.encode(rawExtract),
        'source_dialog_id': sourceDialogId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static DailyRecordModel fromMap(Map<String, dynamic> m) => DailyRecordModel(
        id: m['id'] as String,
        ownerUserId: m['owner_user_id'] as String,
        date: m['date'] as String?,
        breakfast: m['breakfast'] as String?,
        lunch: m['lunch'] as String?,
        dinner: m['dinner'] as String?,
        activities: m['activities'] as String?,
        peopleMet: m['people_met'] as String?,
        placesWent: m['places_went'] as String?,
        mood: m['mood'] as String?,
        rawExtract: m['raw_extract'] == null ? null : Map<String, dynamic>.from(json.decode(m['raw_extract'] as String)),
        sourceDialogId: m['source_dialog_id'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  DailyRecordModel copyWith({
    String? breakfast,
    String? lunch,
    String? dinner,
    String? activities,
    String? peopleMet,
    String? placesWent,
    String? mood,
    Map<String, dynamic>? rawExtract,
  }) =>
      DailyRecordModel(
        id: id,
        ownerUserId: ownerUserId,
        date: date,
        breakfast: breakfast ?? this.breakfast,
        lunch: lunch ?? this.lunch,
        dinner: dinner ?? this.dinner,
        activities: activities ?? this.activities,
        peopleMet: peopleMet ?? this.peopleMet,
        placesWent: placesWent ?? this.placesWent,
        mood: mood ?? this.mood,
        rawExtract: rawExtract ?? this.rawExtract,
        sourceDialogId: sourceDialogId,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
