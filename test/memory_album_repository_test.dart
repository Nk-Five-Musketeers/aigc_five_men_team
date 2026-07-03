import 'package:flutter_test/flutter_test.dart';
import 'package:aigc_five_men_team/data/models/profile_photo.dart';
import 'package:aigc_five_men_team/data/repositories/memory_album_repository.dart';

void main() {
  const forbiddenNarrationFragments = [
    '讲到这张照片',
    '看到一张照片',
    '先看看画面',
    '可以把',
    '可以再多说',
    '还可以补',
    '未确认',
    '待补',
  ];

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

    final requirements =
        input['generation_requirements'] as Map<String, dynamic>;
    expect(requirements['mode'], contains('有声书'));
    expect(requirements['narration_prompt'], contains('边看边听'));
    expect(requirements['narration_prompt'], contains('不要猜测'));
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
          photoTime: '2024春天',
          location: '公园亭子',
          peopleInvolved: '于小晨',
          memoryEventId: 8,
        ),
      ],
    );

    expect(album.albumTitle, '于小晨的回忆图鉴');
    expect(album.albumSubtitle, '慢慢翻，也慢慢听');
    expect(album.cover.subtitle, '慢慢翻，也慢慢听');
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
    expect(album.narration.segments, isNotEmpty);
    expect(album.toJson()['narration']['segments'], isA<List<dynamic>>());

    final narrationText =
        album.narration.segments.map((segment) => segment.text).join();
    for (final fragment in forbiddenNarrationFragments) {
      expect(narrationText, isNot(contains(fragment)));
    }

    final photoItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemType == 'photo_card');
    expect(photoItem.content, contains('在公园亭子里休息'));
    expect(photoItem.content, contains('2024春天'));
    expect(photoItem.content, contains('公园亭子'));
    expect(photoItem.content, contains('于小晨'));

    final profileItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'profile_overview');
    expect(profileItem.content, contains('教师'));
    expect(profileItem.content, contains('听戏'));
    expect(profileItem.content, isNot(contains('职业经历里，有')));
    expect(profileItem.content, isNot(contains('可以记着')));
  });

  test('compose prefers a favorite story photo over avatar for the cover', () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {'name': '于小晨'},
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: [
        ProfilePhotoModel(
          id: 'avatar_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\avatar_001.jpg',
          category: ProfilePhotoCategory.avatar,
        ),
        ProfilePhotoModel(
          id: 'family_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\family_001.jpg',
          category: ProfilePhotoCategory.family,
        ),
        ProfilePhotoModel(
          id: 'favorite_memory_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\favorite_memory_001.jpg',
          category: ProfilePhotoCategory.memory,
          isFavorite: true,
        ),
      ],
    );

    expect(album.cover.recommendedCoverPhotoId, 'favorite_memory_001');
  });

  test('compose prefers a family photo over avatar when no favorite exists',
      () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {'name': '于小晨'},
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: [
        ProfilePhotoModel(
          id: 'avatar_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\avatar_001.jpg',
          category: ProfilePhotoCategory.avatar,
        ),
        ProfilePhotoModel(
          id: 'family_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\family_001.jpg',
          category: ProfilePhotoCategory.family,
        ),
      ],
    );

    expect(album.cover.recommendedCoverPhotoId, 'family_001');
  });

  test('compose uses avatar only after other story photos are exhausted', () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {'name': '于小晨'},
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: [
        ProfilePhotoModel(
          id: 'avatar_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\avatar_001.jpg',
          category: ProfilePhotoCategory.avatar,
        ),
        ProfilePhotoModel(
          id: 'memory_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\memory_001.jpg',
          category: ProfilePhotoCategory.memory,
        ),
      ],
    );

    expect(album.cover.recommendedCoverPhotoId, 'memory_001');
  });

  test('compose skips narration body for photos without story facts', () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {'name': '于小晨'},
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: [
        ProfilePhotoModel(
          id: 'photo_empty',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_empty.jpg',
          category: ProfilePhotoCategory.other,
        ),
      ],
    );

    final photoItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'photo_photo_empty');
    expect(photoItem.content, isEmpty);
    expect(
      album.narration.segments
          .where((segment) => segment.itemId == 'photo_photo_empty'),
      isEmpty,
    );

    final narrationText =
        album.narration.segments.map((segment) => segment.text).join();
    for (final fragment in forbiddenNarrationFragments) {
      expect(narrationText, isNot(contains(fragment)));
    }
  });

  test('compose ignores no-information placeholder values', () {
    final input = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'care_notes': '无',
        'medical_notes': '无特殊注意事项',
        'food_preference': '没有',
      },
      familyMembers: [
        {
          'id': 2,
          'name': '小红',
          'relation': '女儿',
          'notes': '无',
          'contact_freq': '暂无',
          'is_active': 1,
        },
      ],
      memoryEvents: const [],
      dailyLifeRecords: [
        {
          'date': '2026-05-28',
          'breakfast': '无',
          'activities': '暂无',
        },
      ],
      photos: [
        ProfilePhotoModel(
          id: 'photo_no_info',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_no_info.jpg',
          category: ProfilePhotoCategory.other,
          caption: '无',
          peopleInvolved: '未确认',
        ),
      ],
    );

    final daily = input['daily_life_info'] as Map<String, dynamic>;
    expect(daily['favorite_food'], isEmpty);
    expect(daily['health_or_care_notes'], isEmpty);

    final family = input['family_profile'] as Map<String, dynamic>;
    final member = (family['members'] as List).single as Map<String, dynamic>;
    expect(member['notes'], isEmpty);
    expect(member['contact_freq'], isEmpty);

    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'care_notes': '无',
        'medical_notes': '无特殊注意事项',
        'food_preference': '没有',
      },
      familyMembers: [
        {
          'id': 2,
          'name': '小红',
          'relation': '女儿',
          'notes': '无',
          'contact_freq': '暂无',
          'is_active': 1,
        },
      ],
      memoryEvents: const [],
      dailyLifeRecords: [
        {
          'date': '2026-05-28',
          'breakfast': '无',
          'activities': '暂无',
        },
      ],
      photos: [
        ProfilePhotoModel(
          id: 'photo_no_info',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_no_info.jpg',
          category: ProfilePhotoCategory.other,
          caption: '无',
          peopleInvolved: '未确认',
        ),
      ],
    );

    final narrationText =
        album.narration.segments.map((segment) => segment.text).join();
    expect(narrationText, isNot(contains('注意事项为无')));
    expect(narrationText, isNot(contains('一直记着无')));
    expect(narrationText, isNot(contains('无特殊注意事项')));
    expect(narrationText, isNot(contains('暂无')));
    expect(narrationText, isNot(contains('未确认')));

    final familyItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'family_2');
    expect(familyItem.content, '小红是于小晨的女儿。');

    final photoItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'photo_photo_no_info');
    expect(photoItem.content, isEmpty);
  });
}
