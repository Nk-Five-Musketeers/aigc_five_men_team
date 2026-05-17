import 'package:flutter_test/flutter_test.dart';
import 'package:aigc_five_men_team/data/models/profile_photo.dart';

void main() {
  test('ProfilePhotoModel round-trips SQLite fields and json metadata', () {
    final createdAt = DateTime.parse('2026-05-17T08:00:00.000');
    final updatedAt = DateTime.parse('2026-05-17T09:00:00.000');
    final photo = ProfilePhotoModel(
      id: 'photo_1',
      ownerUserId: 'elder_1',
      filePath: r'D:\app-data\photo_1.jpg',
      storageType: ProfilePhotoStorageType.filePath,
      category: ProfilePhotoCategory.family,
      caption: '春节全家福',
      photoTime: '2024-02',
      location: '成都',
      peopleInvolved: '女儿、外孙',
      familyMemberId: 12,
      memoryEventId: 34,
      isFavorite: true,
      metadata: {'source': 'pre_entry'},
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = photo.toMap();

    expect(row['owner_user_id'], 'elder_1');
    expect(row['storage_type'], 'file_path');
    expect(row['category'], 'family');
    expect(row['is_favorite'], 1);
    expect(row['metadata'], '{"source":"pre_entry"}');

    final restored = ProfilePhotoModel.fromMap(row);

    expect(restored.id, 'photo_1');
    expect(restored.filePath, r'D:\app-data\photo_1.jpg');
    expect(restored.storageType, ProfilePhotoStorageType.filePath);
    expect(restored.category, ProfilePhotoCategory.family);
    expect(restored.caption, '春节全家福');
    expect(restored.familyMemberId, 12);
    expect(restored.memoryEventId, 34);
    expect(restored.isFavorite, isTrue);
    expect(restored.metadata, {'source': 'pre_entry'});
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
  });
}
