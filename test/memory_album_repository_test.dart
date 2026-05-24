import 'package:flutter_test/flutter_test.dart';
import 'package:aigc_five_men_team/data/models/profile_photo.dart';
import 'package:aigc_five_men_team/data/repositories/memory_album_repository.dart';

void main() {
  test('buildGenerationInput maps pre-entry rows into album editor input', () {
    final input = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'gender': '男',
        'birth_year': '1980',
        'hometown': '天津津南',
        'current_address': '天津',
        'personality': '踏实',
        'hobbies': '听戏',
        'food_preference': '爱吃面',
        'dialect': '天津话',
      },
      familyMembers: [
        {
          'id': 1,
          'name': '小明',
          'relation': '儿子',
          'location': '北京',
          'contact_freq': '每周电话',
          'notes': '周末常来看望',
          'is_active': 1,
        }
      ],
      memoryEvents: [
        {
          'id': 8,
          'event_time': '1998',
          'title': '搬到新家',
          'description': '一家人在新房门口拍了照片',
          'location': '天津',
          'people_involved': '家人',
          'importance': 4,
          'verified': 1,
        }
      ],
      dailyLifeRecords: [
        {
          'date': '2026-05-24',
          'breakfast': '粥',
          'activities': '散步',
        }
      ],
      photos: [
        ProfilePhotoModel(
          id: 'photo_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_001.jpg',
          category: ProfilePhotoCategory.memory,
          caption: '在公园亭子里休息',
          photoTime: '2024春天',
          location: '公园亭子',
          peopleInvolved: '于小晨',
          memoryEventId: 8,
        ),
      ],
    );

    final elder = input['elder_profile'] as Map<String, dynamic>;
    expect(elder['name'], '于小晨');
    expect(elder['hometown'], '天津津南');

    final family = input['family_profile'] as Map<String, dynamic>;
    expect(family['children'], isNotEmpty);
    expect((family['members'] as List).single['name'], '小明');

    final photos = input['photo_analysis_results'] as List<dynamic>;
    expect(photos.single['photo_id'], 'photo_001');
    expect(photos.single['scene'], '公园亭子');
  });

  test('compose creates chapters, photo cards, timeline and questions', () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'hometown': '天津津南',
        'career': '教师',
        'hobbies': '听戏',
      },
      familyMembers: [
        {
          'id': 1,
          'name': '小明',
          'relation': '儿子',
          'notes': '老人常念叨他',
          'is_active': 1,
        }
      ],
      memoryEvents: [
        {
          'id': 8,
          'event_time': '1998',
          'title': '搬到新家',
          'description': '一家人在新房门口拍了照片',
          'photo_paths': r'["D:\\app-data\\photo_001.jpg"]',
        }
      ],
      dailyLifeRecords: const [],
      photos: [
        ProfilePhotoModel(
          id: 'photo_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_001.jpg',
          category: ProfilePhotoCategory.memory,
          caption: '在公园亭子里休息',
          memoryEventId: 8,
        ),
      ],
    );

    expect(album.albumTitle, '于小晨的回忆图鉴');
    expect(album.hasContent, isTrue);
    expect(
      album.chapters.any((chapter) => chapter.chapterType == 'photo_memory'),
      isTrue,
    );
    expect(
      album.chapters
          .expand((chapter) => chapter.items)
          .any((item) => item.itemType == 'photo_card'),
      isTrue,
    );
    expect(album.timeline.single.relatedPhotoIds, contains('photo_001'));
    expect(album.toJson()['chapters'], isA<List<dynamic>>());
  });
}
