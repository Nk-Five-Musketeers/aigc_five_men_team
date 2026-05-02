import 'dart:convert';

class NearbyPersonModel {
  NearbyPersonModel({
    required this.id,
    required this.ownerUserId,
    this.name,
    this.relation,
    this.phone,
    this.address,
    this.note,
    this.isEmergencyContact = false,
    this.distanceMeters,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String ownerUserId;
  final String? name;
  final String? relation;
  final String? phone;
  final String? address;
  final String? note;
  final bool isEmergencyContact;
  final double? distanceMeters;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'name': name,
        'relation': relation,
        'phone': phone,
        'address': address,
        'note': note,
        'is_emergency_contact': isEmergencyContact ? 1 : 0,
        'distance_meters': distanceMeters,
        'metadata': metadata == null ? null : _encode(metadata!),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static NearbyPersonModel fromMap(Map<String, dynamic> m) => NearbyPersonModel(
        id: m['id'] as String,
        ownerUserId: m['owner_user_id'] as String,
        name: m['name'] as String?,
        relation: m['relation'] as String?,
        phone: m['phone'] as String?,
        address: m['address'] as String?,
        note: m['note'] as String?,
        isEmergencyContact: (m['is_emergency_contact'] as int? ?? 0) == 1,
        distanceMeters: (m['distance_meters'] as num?)?.toDouble(),
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
    String? phone,
    String? address,
    String? note,
    bool? isEmergencyContact,
    double? distanceMeters,
    Map<String, dynamic>? metadata,
  }) =>
      NearbyPersonModel(
        id: id,
        ownerUserId: ownerUserId,
        name: name ?? this.name,
        relation: relation ?? this.relation,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        note: note ?? this.note,
        isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        metadata: metadata ?? this.metadata,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static String _encode(Object o) => const JsonEncoder().convert(o);
  static Map<String, dynamic> _decode(String s) =>
      Map<String, dynamic>.from(const JsonDecoder().convert(s));
}
