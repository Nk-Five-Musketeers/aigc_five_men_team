class PreEntryMapper {
  PreEntryMapper._();

  static Map<String, dynamic> buildFamilyMemberPatchFromNearby(
    Map<String, dynamic> nearby,
  ) {
    final location = _text(nearby['location']) ?? _text(nearby['address']);
    return {
      'owner_user_id': _text(nearby['owner_user_id']),
      'name': _text(nearby['name']),
      'relation': _text(nearby['relation']),
      'photo_path': _text(nearby['photo_path']),
      'birthday': _text(nearby['birthday']),
      'location': location,
      'contact_freq': _text(nearby['contact_freq']),
      'notes': _text(nearby['note']),
      'is_active': nearby['is_active'] is int ? nearby['is_active'] : 1,
    }..removeWhere((_, value) => value == null);
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
