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
    expect(familyItem.content, '小红是于小晨的女儿。');

    final photoItem = album.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'photo_photo_no_info');
    expect(photoItem.content, isEmpty);
  });

  test('buildPolishInput exposes source facts and local text draft', () {
    final generationInput = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'hometown': '天津津南',
        'career': '教师',
        'hobbies': '听戏',
      },
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: const [],
    );
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {
        'name': '于小晨',
        'hometown': '天津津南',
        'career': '教师',
        'hobbies': '听戏',
      },
      familyMembers: const [],
      memoryEvents: const [],
      dailyLifeRecords: const [],
      photos: const [],
    );

    final polishInput = MemoryAlbumComposer.buildPolishInput(
      album: album,
      generationInput: generationInput,
    );

    final facts = polishInput['source_facts'] as Map<String, dynamic>;
    expect(facts['elder_profile']['name'], '于小晨');
    expect(facts.containsKey('generation_requirements'), isFalse);

    final draft = polishInput['local_album_draft'] as Map<String, dynamic>;
    expect(draft['album_title'], '于小晨的回忆图鉴');
    expect(draft['elder_profile_card']['content'], contains('教师'));
    expect(draft['chapters'], isA<List<dynamic>>());
  });

  test(
      'applyPolishedTexts merges safe text and keeps empty photo stories empty',
      () {
    final album = MemoryAlbumComposer.compose(
      ownerUserId: 'elder_1',
      user: {
        'name': '张桂芳',
        'career': '纺织厂打工',
        'hobbies': '看电视',
        'food_preference': '清淡，爱吃饺子',
        'personality': '温和而坚定',
        'dialect': '天津话',
      },
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

    final polished = MemoryAlbumComposer.applyPolishedTexts(album, {
      'cover_text': '根据资料，张桂芳的故事正在展开。',
      'opening_content': '这是张桂芳的回忆，也是家人一起记住的日子。',
      'elder_profile_content': '张桂芳年轻时在纺织厂工作，那是一段踏实忙碌的日子。',
      'chapters': [
        {
          'chapter_id': 'profile',
          'chapter_intro': '张桂芳的故事，藏在家人熟悉的一件件小事里。',
          'items': [
            {
              'item_id': 'profile_overview',
              'content': '张桂芳年轻时在纺织厂工作，那是一段踏实忙碌的日子。平时在家里，她喜欢看电视，也喜欢清淡的饭菜和饺子。',
            },
          ],
        },
        {
          'chapter_id': 'photo_memory',
          'chapter_intro': '这些照片留下了张桂芳生命里的一个个片刻。',
          'items': [
            {
              'item_id': 'photo_photo_empty',
              'content': '这是一段模型不能补写的照片故事。',
            },
          ],
        },
      ],
      'ending_content': '张桂芳的日子还在继续，家人的记挂也还在继续。',
    });

    expect(polished.cover.coverText, album.cover.coverText);
    expect(polished.opening.content, contains('一起记住的日子'));
    expect(polished.elderProfileCard.content, contains('踏实忙碌'));
    expect(polished.notes.rewrittenParts, contains('AI润色正文'));

    final profileItem = polished.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'profile_overview');
    expect(profileItem.content, contains('平时在家里'));

    final emptyPhotoItem = polished.chapters
        .expand((chapter) => chapter.items)
        .singleWhere((item) => item.itemId == 'photo_photo_empty');
    expect(emptyPhotoItem.content, isEmpty);

    final narrationText =
        polished.narration.segments.map((segment) => segment.text).join();
    expect(narrationText, contains('踏实忙碌'));
    expect(narrationText, isNot(contains('模型不能补写')));
  });
}
