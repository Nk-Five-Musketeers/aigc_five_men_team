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
    '有一段和',
    '平时的生活里',
    '家人记得',
    '职业为',
    '爱好是',
    '籍贯是',
    '性格是',
    '该老人',
    '此照片展示了',
    '该图鉴记录了',
    '我们猜想',
    '或许',
    '也许',
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
    expect(requirements['narration_prompt'], contains('少写不补'));
    expect(requirements['narration_prompt'], contains('不用“也许”“或许”“我们猜想”'));
  });

  test('storyKeywordsForInput dedupes pre-entry facts before AI generation',
      () {
    final input = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'hometown': '天津津南',
        'career': '教师',
        'food_preference': '吃饭是老人的饮食习惯',
      },
      familyMembers: [
        {
          'id': 1,
          'name': '小明',
          'relation': '儿子',
          'notes': '教师',
          'is_active': 1,
        },
      ],
      memoryEvents: [
        {
          'id': 8,
          'event_time': '1998',
          'title': '搬到新家',
          'description': '一家人在新房门口拍了照片',
          'location': '天津津南',
          'people_involved': '小明',
        },
      ],
      dailyLifeRecords: [
        {
          'date': '2026-05-28',
          'breakfast': '吃饭',
          'activities': '散步',
        },
      ],
      photos: [
        ProfilePhotoModel(
          id: 'photo_001',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_001.jpg',
          category: ProfilePhotoCategory.memory,
          caption: '一家人在新房门口拍了照片',
          location: '天津津南',
          peopleInvolved: '小明',
        ),
      ],
    );

    final keywords = MemoryAlbumComposer.storyKeywordsForInput(input);
    final values = keywords.map((item) => item['value']).toList();

    expect(values, contains('于小晨'));
    expect(values, contains('天津津南'));
    expect(values, contains('教师'));
    expect(values, contains('搬到新家'));
    expect(values.where((value) => value == '教师'), hasLength(1));
    expect(values.where((value) => value == '天津津南'), hasLength(1));
    expect(values, isNot(contains('吃饭')));
    expect(values, isNot(contains('吃饭是老人的饮食习惯')));
  });

  test('dedupePhotosByStoryContent keeps one photo for repeated image story',
      () {
    final photos = [
      ProfilePhotoModel(
        id: 'photo_a',
        ownerUserId: 'elder_1',
        filePath: r'D:\app-data\a.jpg',
        category: ProfilePhotoCategory.memory,
        caption: '一家人在新房门口拍了照片',
        location: '天津津南',
        peopleInvolved: '小明',
        createdAt: DateTime(2026, 1, 2),
      ),
      ProfilePhotoModel(
        id: 'photo_b',
        ownerUserId: 'elder_1',
        filePath: r'D:\app-data\b.jpg',
        category: ProfilePhotoCategory.memory,
        caption: '一家人在新房门口拍了照片',
        location: '天津津南',
        peopleInvolved: '小明',
        isFavorite: true,
        createdAt: DateTime(2026, 1, 3),
      ),
      ProfilePhotoModel(
        id: 'photo_c',
        ownerUserId: 'elder_1',
        filePath: r'D:\app-data\c.jpg',
        category: ProfilePhotoCategory.daily,
        caption: '在公园亭子里休息',
        location: '公园亭子',
        peopleInvolved: '于小晨',
      ),
    ];

    final deduped = MemoryAlbumComposer.dedupePhotosByStoryContent(photos);

    expect(deduped.map((photo) => photo.id), ['photo_b', 'photo_c']);
  });

  test('compose only creates one photo card for repeated image content', () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {'name': '于小晨'},
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: [
        ProfilePhotoModel(
          id: 'photo_a',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\a.jpg',
          category: ProfilePhotoCategory.memory,
          caption: '一家人在新房门口拍了照片',
          location: '天津津南',
          peopleInvolved: '小明',
        ),
        ProfilePhotoModel(
          id: 'photo_b',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\b.jpg',
          category: ProfilePhotoCategory.memory,
          caption: '一家人在新房门口拍了照片',
          location: '天津津南',
          peopleInvolved: '小明',
          isFavorite: true,
        ),
      ],
    );

    final photoItems = album.chapters
        .expand((chapter) => chapter.items)
        .where((item) => item.itemType == 'photo_card')
        .toList();

    expect(photoItems, hasLength(1));
    expect(photoItems.single.photoId, 'photo_b');
  });

  test('compose removes repeated concrete story facts across sections', () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'hobbies': '听李老师讲课',
      },
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: [
        ProfilePhotoModel(
          id: 'photo_lecture',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\lecture.jpg',
          category: ProfilePhotoCategory.memory,
          caption: '听李老师讲课',
        ),
      ],
    );

    final narrationText =
        album.narration.segments.map((segment) => segment.text).join();
    expect(RegExp('听李老师').allMatches(narrationText), hasLength(1));
    expect(album.notes.rewrittenParts.join(), contains('重复故事内容'));
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
    expect(familyItem.content, '我们也记得，小红是你的女儿。');

    final photoItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'photo_photo_no_info');
    expect(photoItem.content, isEmpty);
  });

  test('compose filters semantically weak pre-entry values into notes', () {
    final input = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'food_preference': '吃饭是老人的饮食习惯',
        'care_notes': '照看老人',
      },
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: [
        {
          'date': '2026-05-28',
          'breakfast': '吃饭',
          'activities': '日常活动',
        },
      ],
      photos: [
        ProfilePhotoModel(
          id: 'photo_generic',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_generic.jpg',
          category: ProfilePhotoCategory.other,
          caption: '这是一张照片',
        ),
      ],
    );

    final daily = input['daily_life_info'] as Map<String, dynamic>;
    expect(daily['favorite_food'], isEmpty);
    expect(daily['health_or_care_notes'], isEmpty);
    final dailyHabits = daily['daily_habits'] as List<dynamic>;
    expect((dailyHabits.single as Map<String, dynamic>)['breakfast'], isEmpty);

    final warnings = input['input_quality_warnings'] as List<dynamic>;
    expect(warnings.join(), contains('饮食习惯'));
    expect(warnings.join(), contains('吃饭是老人的饮食习惯'));

    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'food_preference': '吃饭是老人的饮食习惯',
        'care_notes': '照看老人',
      },
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: [
        {
          'date': '2026-05-28',
          'breakfast': '吃饭',
          'activities': '日常活动',
        },
      ],
      photos: [
        ProfilePhotoModel(
          id: 'photo_generic',
          ownerUserId: 'elder_1',
          filePath: r'D:\app-data\photo_generic.jpg',
          category: ProfilePhotoCategory.other,
          caption: '这是一张照片',
        ),
      ],
    );

    final narrationText =
        album.narration.segments.map((segment) => segment.text).join();
    expect(narrationText, isNot(contains('吃饭是老人的饮食习惯')));
    expect(narrationText, isNot(contains('照看老人')));
    expect(narrationText, isNot(contains('这是一张照片')));
    expect(album.notes.possibleConflicts.join(), contains('饮食习惯'));
    expect(album.notes.possibleConflicts.join(), contains('照片'));
  });

  test('compose keeps concrete details from field-style sentences', () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'food_preference': '饮食习惯是爱吃面',
        'career': '职业经历是教师',
      },
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: const [],
    );

    final profileItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'profile_overview');
    expect(profileItem.content, contains('爱吃面'));
    expect(profileItem.content, contains('教师'));
    expect(profileItem.content, isNot(contains('饮食习惯是')));
    expect(profileItem.content, isNot(contains('职业经历是')));
    expect(album.notes.possibleConflicts.join(), isNot(contains('爱吃面')));
  });
}
