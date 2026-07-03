part of 'local_database.dart';

class StoredUserDataBundle {
  const StoredUserDataBundle({
    this.user,
    this.familyMembers = const [],
    this.memoryEvents = const [],
    this.dailyLifeRecords = const [],
    this.nearbyPeople = const [],
    this.profilePhotoRows = const [],
    this.pendingRelationConflicts = const [],
    this.cognitiveTests = const [],
  });

  final Map<String, dynamic>? user;
  final List<Map<String, dynamic>> familyMembers;
  final List<Map<String, dynamic>> memoryEvents;
  final List<Map<String, dynamic>> dailyLifeRecords;
  final List<Map<String, dynamic>> nearbyPeople;
  final List<Map<String, dynamic>> profilePhotoRows;
  final List<Map<String, dynamic>> pendingRelationConflicts;
  final List<Map<String, dynamic>> cognitiveTests;

  bool get hasAnyData =>
      user != null ||
      familyMembers.isNotEmpty ||
      memoryEvents.isNotEmpty ||
      dailyLifeRecords.isNotEmpty ||
      nearbyPeople.isNotEmpty ||
      profilePhotoRows.isNotEmpty;
}
