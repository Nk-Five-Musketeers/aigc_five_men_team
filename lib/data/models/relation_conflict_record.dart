/// 本地「人物关系」字段与聊天记录中新信息不一致时的待确认项。
class RelationConflictRecord {
  RelationConflictRecord({
    required this.id,
    required this.ownerUserId,
    this.nearbyPersonId,
    required this.personName,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    this.sourceMessageId,
    required this.createdAt,
  });

  final String id;
  final String ownerUserId;
  final String? nearbyPersonId;
  final String personName;
  /// relation | note | phone
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String? sourceMessageId;
  final DateTime createdAt;

  String get fieldLabel {
    switch (fieldName) {
      case 'relation':
        return '称谓/关系';
      case 'note':
        return '备注';
      case 'phone':
        return '电话';
      default:
        return fieldName;
    }
  }

  static RelationConflictRecord fromRow(Map<String, dynamic> m) {
    return RelationConflictRecord(
      id: m['id'] as String,
      ownerUserId: m['owner_user_id'] as String,
      nearbyPersonId: m['nearby_person_id'] as String?,
      personName: m['person_name'] as String,
      fieldName: m['field_name'] as String,
      oldValue: m['old_value'] as String?,
      newValue: m['new_value'] as String?,
      sourceMessageId: m['source_message_id'] as String?,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
