import 'dart:convert';

class UserModel {
  UserModel(
      {required this.id,
      this.name,
      this.avatarPath,
      this.birthYear,
      this.hometown,
      this.career,
      this.hobbies,
      this.foodPreference,
      this.personality,
      this.taboo,
      this.dialect,
      this.gender,
      this.currentAddress,
      this.careNotes,
      this.medicalNotes,
      this.metadata,
      DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String? name;
  final String? avatarPath;
  final String? birthYear;
  final String? hometown;
  final String? career;
  final String? hobbies;
  final String? foodPreference;
  final String? personality;
  final String? taboo;
  final String? dialect;
  final String? gender;
  final String? currentAddress;
  final String? careNotes;
  final String? medicalNotes;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'avatar_path': avatarPath,
        'birth_year': birthYear,
        'hometown': hometown,
        'career': career,
        'hobbies': hobbies,
        'food_preference': foodPreference,
        'personality': personality,
        'taboo': taboo,
        'dialect': dialect,
        'gender': gender,
        'current_address': currentAddress,
        'care_notes': careNotes,
        'medical_notes': medicalNotes,
        'metadata': metadata == null ? null : _encode(metadata!),
        'created_at': createdAt.toIso8601String(),
      };

  static UserModel fromMap(Map<String, dynamic> m) => UserModel(
        id: m['id'] as String,
        name: m['name'] as String?,
        avatarPath: m['avatar_path'] as String?,
        birthYear: m['birth_year'] as String?,
        hometown: m['hometown'] as String?,
        career: m['career'] as String?,
        hobbies: m['hobbies'] as String?,
        foodPreference: m['food_preference'] as String?,
        personality: m['personality'] as String?,
        taboo: m['taboo'] as String?,
        dialect: m['dialect'] as String?,
        gender: m['gender'] as String?,
        currentAddress: m['current_address'] as String?,
        careNotes: m['care_notes'] as String?,
        medicalNotes: m['medical_notes'] as String?,
        metadata:
            m['metadata'] == null ? null : _decode(m['metadata'] as String),
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  static String _encode(Object o) => const JsonEncoder().convert(o);
  static Map<String, dynamic> _decode(String s) =>
      Map<String, dynamic>.from(const JsonDecoder().convert(s));
}
