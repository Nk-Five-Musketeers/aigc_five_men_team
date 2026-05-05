import 'dart:convert';

class NearbyPersonModel {
  NearbyPersonModel({
    required this.id,
    required this.ownerUserId,
    this.name,
    this.relation,
    this.photoPath,
    this.phone,
    this.birthday,
    this.location,
    this.address,
    this.contactFreq,
    this.note,
    this.isEmergencyContact = false,
    this.distanceMeters,
    this.isActive = true,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String ownerUserId;
  final String? name;
  final String? relation;
  final String? photoPath;
  final String? phone;
  final String? birthday;
  final String? location;
  final String? contactFreq;
  final String? address;
  final String? note;
  final bool isEmergencyContact;
  final double? distanceMeters;
  final bool isActive;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'name': name,
        'relation': relation,
      'photo_path': photoPath,
      'phone': phone,
      'birthday': birthday,
      'location': location,
      'address': address,
      'contact_freq': contactFreq,
      'note': note,
      'is_emergency_contact': isEmergencyContact ? 1 : 0,
      'distance_meters': distanceMeters,
      'is_active': isActive ? 1 : 0,
      'metadata': metadata == null ? null : _encode(metadata!),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      };

    static NearbyPersonModel fromMap(Map<String, dynamic> m) => NearbyPersonModel(
      id: m['id'] as String,
      ownerUserId: m['owner_user_id'] as String,
      name: m['name'] as String?,
      relation: m['relation'] as String?,
      photoPath: m['photo_path'] as String?,
      phone: m['phone'] as String?,
      birthday: m['birthday'] as String?,
      location: m['location'] as String?,
      address: m['address'] as String?,
      contactFreq: m['contact_freq'] as String?,
      note: m['note'] as String?,
      isEmergencyContact: (m['is_emergency_contact'] as int? ?? 0) == 1,
      distanceMeters: (m['distance_meters'] as num?)?.toDouble(),
      isActive: (m['is_active'] as int? ?? 1) == 1,
      metadata:
        m['metadata'] == null ? null : _decode(m['metadata'] as String),
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
        DateTime.now(),
      updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ??
        DateTime.now(),
      );

  NearbyPersonModel copyWith({
    String? name,
    String? relation,
    String? photoPath,
    String? phone,
    String? birthday,
    String? location,
    String? address,
    String? contactFreq,
    String? note,
    bool? isEmergencyContact,
    double? distanceMeters,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) =>
      NearbyPersonModel(
        id: id,
        ownerUserId: ownerUserId,
        name: name ?? this.name,
        relation: relation ?? this.relation,
        photoPath: photoPath ?? this.photoPath,
        phone: phone ?? this.phone,
        birthday: birthday ?? this.birthday,
        location: location ?? this.location,
        address: address ?? this.address,
        contactFreq: contactFreq ?? this.contactFreq,
        note: note ?? this.note,
        isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        isActive: isActive ?? this.isActive,
        metadata: metadata ?? this.metadata,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static String _encode(Object o) => const JsonEncoder().convert(o);
  static Map<String, dynamic> _decode(String s) =>
      Map<String, dynamic>.from(const JsonDecoder().convert(s));
}
