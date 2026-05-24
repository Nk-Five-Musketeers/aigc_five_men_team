import 'dart:convert';

import '../local_db/local_database.dart';
import '../models/memory_album.dart';
import '../models/profile_photo.dart';

class MemoryAlbumDraft {
  const MemoryAlbumDraft({
    required this.album,
    required this.photos,
    required this.generationInput,
  });

  final MemoryAlbum album;
  final List<ProfilePhotoModel> photos;
  final Map<String, dynamic> generationInput;

  Map<String, ProfilePhotoModel> get photosById => {
        for (final photo in photos) photo.id: photo,
      };
}

class MemoryAlbumRepository {
  Future<MemoryAlbumDraft> buildForUser(String ownerUserId) async {
    final user = await LocalDatabase.getUserById(ownerUserId);
    final familyMembers =
        await LocalDatabase.listFamilyMembersForUser(ownerUserId);
    final memoryEvents =
        await LocalDatabase.listMemoryEventsForUser(ownerUserId);
    final dailyLifeRecords =
        await LocalDatabase.listDailyLifeRecordsForUser(ownerUserId, limit: 12);
    final photos = await LocalDatabase.listProfilePhotosForUser(ownerUserId);

    final generationInput = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: ownerUserId,
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: photos,
    );
    final album = MemoryAlbumComposer.compose(
      ownerUserId: ownerUserId,
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: photos,
    );

    return MemoryAlbumDraft(
      album: album,
      photos: photos,
      generationInput: generationInput,
    );
  }
}

class MemoryAlbumComposer {
  MemoryAlbumComposer._();

  static Map<String, dynamic> buildGenerationInput({
    required String ownerUserId,
    required Map<String, dynamic>? user,
    required List<Map<String, dynamic>> familyMembers,
    required List<Map<String, dynamic>> memoryEvents,
    required List<Map<String, dynamic>> dailyLifeRecords,
    required List<ProfilePhotoModel> photos,
  }) {
    final children = familyMembers
        .where((row) => _isChildRelation(_text(row['relation'])))
        .map(_familyInputRow)
        .toList();
    final grandchildren = familyMembers
        .where((row) => _isGrandchildRelation(_text(row['relation'])))
        .map(_familyInputRow)
        .toList();
    final spouse = familyMembers.firstWhere(
      (row) => _isSpouseRelation(_text(row['relation'])),
      orElse: () => const <String, dynamic>{},
    );

    return {
      'existing_memory_album': {
        'album_title': '未命名',
        'chapters': <dynamic>[],
        'photo_cards': <dynamic>[],
      },
      'elder_profile': {
        'name': _text(user?['name']),
        'gender': _text(user?['gender']),
        'birth_year_or_age': _text(user?['birth_year']),
        'hometown': _text(user?['hometown']),
        'current_location': _text(user?['current_address']),
        'personality': _text(user?['personality']),
        'hobbies': _text(user?['hobbies']),
        'common_words': _text(user?['dialect']),
        'important_labels': _importantLabels(user),
      },
      'family_profile': {
        'spouse': _text(spouse['name']),
        'children': children,
        'grandchildren': grandchildren,
        'main_caregiver': _mainCaregiver(familyMembers),
        'family_relationship_notes': _familyNotes(familyMembers),
        'members': familyMembers.map(_familyInputRow).toList(),
      },
      'life_experience': {
        'education': '',
        'work': _text(user?['career']),
        'important_events': memoryEvents.map(_memoryInputRow).toList(),
        'memorable_stories': memoryEvents
            .map((row) => _text(row['description']))
            .where((text) => text.isNotEmpty)
            .toList(),
        'family_stories': familyMembers
            .map((row) => _text(row['notes']))
            .where((text) => text.isNotEmpty)
            .toList(),
      },
      'daily_life_info': {
        'daily_habits': dailyLifeRecords.map(_dailyInputRow).toList(),
        'favorite_food': _text(user?['food_preference']),
        'favorite_places': _favoritePlaces(photos, memoryEvents),
        'objects_often_used': <String>[],
        'health_or_care_notes': [
          _text(user?['care_notes']),
          _text(user?['medical_notes']),
        ].where((text) => text.isNotEmpty).join('；'),
      },
      'photo_analysis_results':
          photos.map((photo) => _photoInputRow(photo)).toList(),
      'family_notes': photos
          .where((photo) => _text(photo.caption).isNotEmpty)
          .map((photo) => {
                'photo_id': photo.id,
                'note': _text(photo.caption),
              })
          .toList(),
      'generation_requirements': {
        'tone': '温暖、自然、娓娓道来',
        'target_reader': '老人本人和家属',
        'length': '中等',
        'allow_rebuild_album': true,
        'output_language': '中文',
        'source': 'local_pre_entry',
        'owner_user_id': ownerUserId,
      },
    };
  }

  static MemoryAlbum compose({
    required String ownerUserId,
    required Map<String, dynamic>? user,
    required List<Map<String, dynamic>> familyMembers,
    required List<Map<String, dynamic>> memoryEvents,
    required List<Map<String, dynamic>> dailyLifeRecords,
    required List<ProfilePhotoModel> photos,
  }) {
    final name = _text(user?['name']);
    final elderName = name.isEmpty ? '家里的长辈' : name;
    final profileItems = _profileItems(user);
    final coverPhoto = _pickCoverPhoto(photos);
    final chapters = <MemoryAlbumChapter>[];
    final familyQuestions = <FamilyQuestion>[];
    final missing = <String>[];

    if (profileItems.isEmpty) {
      missing.add('老人基本信息');
    }
    if (familyMembers.isEmpty) {
      missing.add('亲属信息');
      familyQuestions.add(const FamilyQuestion(
        question: '家里人平时怎么称呼老人？',
        reason: '有了熟悉的称呼，家里人的位置会更清楚。',
      ));
    }
    if (memoryEvents.isEmpty) {
      missing.add('人生经历');
      familyQuestions.add(const FamilyQuestion(
        question: '有没有一件老人常提起、家里人也记得的往事？',
        reason: '这样的往事适合慢慢展开成一段故事。',
      ));
    }
    if (photos.isEmpty) {
      missing.add('照片');
      familyQuestions.add(const FamilyQuestion(
        question: '可以先选一张老人状态自然的照片吗？',
        reason: '看到熟悉的照片，话就容易慢慢说起来。',
      ));
    }

    final profileChapter = _buildProfileChapter(elderName, user);
    if (profileChapter.items.isNotEmpty) {
      chapters.add(profileChapter);
    }

    final familyChapter = _buildFamilyChapter(familyMembers);
    if (familyChapter.items.isNotEmpty) {
      chapters.add(familyChapter);
    }

    final lifeChapter = _buildLifeChapter(memoryEvents, photos);
    if (lifeChapter.items.isNotEmpty) {
      chapters.add(lifeChapter);
    }

    final photoChapter = _buildPhotoChapter(
      photos: photos,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      user: user,
      familyQuestions: familyQuestions,
    );
    if (photoChapter.items.isNotEmpty) {
      chapters.add(photoChapter);
    }

    final dailyChapter = _buildDailyChapter(dailyLifeRecords, user);
    if (dailyChapter.items.isNotEmpty) {
      chapters.add(dailyChapter);
    }

    final timeline = _buildTimeline(memoryEvents, photos);
    final addedParts = chapters.map((chapter) => chapter.chapterTitle).toList();

    return MemoryAlbum(
      albumId: 'album_$ownerUserId',
      albumTitle: '$elderName的回忆图鉴',
      albumSubtitle: _albumSubtitle(user, familyMembers, memoryEvents, photos),
      cover: AlbumCover(
        title: elderName,
        subtitle: _coverSubtitle(user),
        coverText: _coverText(elderName, coverPhoto, photos),
        recommendedCoverPhotoId: coverPhoto?.id ?? '',
      ),
      opening: AlbumText(
        title: '慢慢翻',
        content: _openingText(elderName, familyMembers, memoryEvents, photos),
      ),
      elderProfileCard: ElderProfileCard(
        title: '关于$elderName',
        content: _elderProfileContent(elderName, user),
        profileItems: profileItems,
      ),
      chapters: chapters,
      timeline: timeline,
      ending: AlbumText(
        title: '还可以继续补上',
        content: _endingText(elderName, missing),
      ),
      familyQuestions: _dedupeQuestions(familyQuestions).take(8).toList(),
      notes: AlbumNotes(
        usedExistingAlbum: false,
        rewrittenParts: const <String>[],
        addedParts: addedParts,
        possibleConflicts: const <String>[],
        missingInformation: missing,
      ),
    );
  }

  static MemoryAlbumChapter _buildProfileChapter(
    String elderName,
    Map<String, dynamic>? user,
  ) {
    final items = <MemoryAlbumItem>[];
    final career = _text(user?['career']);
    final hobbies = _text(user?['hobbies']);
    final food = _text(user?['food_preference']);
    final personality = _text(user?['personality']);
    final dialect = _text(user?['dialect']);
    final care = _text(user?['care_notes']);

    if ([career, hobbies, food, personality, dialect, care]
        .any((text) => text.isNotEmpty)) {
      items.add(MemoryAlbumItem(
        itemId: 'profile_overview',
        itemType: 'text_card',
        title: '日子里的样子',
        content: [
          if (career.isNotEmpty) '$elderName曾经的职业经历里，有“$career”。',
          if (hobbies.isNotEmpty) '平时喜欢的事里，有“$hobbies”。',
          if (food.isNotEmpty) '饮食习惯里也有熟悉的味道：$food。',
          if (personality.isNotEmpty) '说起性格，可以记着“$personality”。',
          if (dialect.isNotEmpty) '他说话里带着$dialect的亲切感。',
          if (care.isNotEmpty) '平时照看时，也记得：$care。',
        ].join(' '),
        relatedProfileFields: const [
          'career',
          'hobbies',
          'food_preference',
          'personality',
          'dialect',
          'care_notes',
        ],
      ));
    }

    return MemoryAlbumChapter(
      chapterId: 'profile',
      chapterTitle: '一个人的轮廓',
      chapterSubtitle: '先记住那些最熟悉的小事',
      chapterIntro: '姓名、籍贯、爱好和习惯，放在一起，就是家人眼里熟悉的样子。',
      chapterType: 'profile',
      items: items,
    );
  }

  static MemoryAlbumChapter _buildFamilyChapter(
    List<Map<String, dynamic>> familyMembers,
  ) {
    final items = <MemoryAlbumItem>[];
    for (final row in familyMembers.take(12)) {
      final name = _text(row['name']);
      if (name.isEmpty) continue;
      final relation = _text(row['relation']);
      final location = _text(row['location']);
      final contact = _text(row['contact_freq']);
      final notes = _text(row['notes']);
      final active = _bool01(row['is_active'], defaultValue: true);
      items.add(MemoryAlbumItem(
        itemId: 'family_${row['id'] ?? name}',
        itemType: 'profile_card',
        title: relation.isEmpty ? name : '$relation · $name',
        content: [
          relation.isEmpty ? '$name是家里记下的重要亲友。' : '$name是$relation。',
          if (location.isNotEmpty) '现在常在$location。',
          if (contact.isNotEmpty) '联系频率写着：$contact。',
          if (notes.isNotEmpty) notes,
          if (!active) '说到这段关系时，可以把语气放得更轻一些。',
        ].join(' '),
        relatedProfileFields: const ['family_members'],
        familyQuestions: [
          if (notes.isEmpty) '家里人最常用什么称呼叫$name？',
          if (contact.isEmpty) '平时$name和老人多久联系一次？',
        ],
      ));
    }

    return MemoryAlbumChapter(
      chapterId: 'family',
      chapterTitle: '家里人和牵挂',
      chapterSubtitle: '把称呼、地点和相处提醒放在一起',
      chapterIntro: '亲属信息不是名单，而是老人每天可能想起的人。',
      chapterType: 'family',
      items: items,
    );
  }

  static MemoryAlbumChapter _buildLifeChapter(
    List<Map<String, dynamic>> memoryEvents,
    List<ProfilePhotoModel> photos,
  ) {
    final items = <MemoryAlbumItem>[];
    for (final row in memoryEvents.take(12)) {
      final title = _text(row['title']);
      final desc = _text(row['description']);
      if (title.isEmpty && desc.isEmpty) continue;
      final time = _text(row['event_time']);
      final location = _text(row['location']);
      final people = _text(row['people_involved']);
      final emotion = _text(row['emotion']);
      items.add(MemoryAlbumItem(
        itemId: 'life_${row['id'] ?? items.length}',
        itemType: 'timeline_card',
        title: title.isEmpty ? '一段往事' : title,
        content: [
          if (time.isNotEmpty) '$time，',
          if (location.isNotEmpty) '地点在$location。',
          if (desc.isNotEmpty) desc,
          if (people.isNotEmpty) '这段经历里提到的人有：$people。',
          if (emotion.isNotEmpty) '当时留下的感受是“$emotion”。',
        ].join(' '),
        photoId: _firstPhotoIdForEvent(row, photos),
        relatedProfileFields: const ['memory_events'],
        familyQuestions: [
          if (desc.length < 12) '这段经历能不能再补一两句细节？',
          if (time.isEmpty) '这件事大概发生在哪一年或哪个阶段？',
        ],
      ));
    }
    return MemoryAlbumChapter(
      chapterId: 'life_experience',
      chapterTitle: '走过的日子',
      chapterSubtitle: '把那些重要时刻轻轻放好',
      chapterIntro: '有些往事已经有了时间和地点，有些还只有一句话，都可以先留下。',
      chapterType: 'life_experience',
      items: items,
    );
  }

  static MemoryAlbumChapter _buildPhotoChapter({
    required List<ProfilePhotoModel> photos,
    required List<Map<String, dynamic>> familyMembers,
    required List<Map<String, dynamic>> memoryEvents,
    required Map<String, dynamic>? user,
    required List<FamilyQuestion> familyQuestions,
  }) {
    final familyById = {
      for (final row in familyMembers)
        if (_int(row['id']) != null) _int(row['id'])!: row,
    };
    final memoryById = {
      for (final row in memoryEvents)
        if (_int(row['id']) != null) _int(row['id'])!: row,
    };
    final items = <MemoryAlbumItem>[];

    for (final photo in photos) {
      final questions = _photoQuestions(photo).take(3).toList();
      familyQuestions.addAll(questions.map(
        (question) => FamilyQuestion(
          question: question,
          reason: '多一点细节，翻到这张照片时就更容易想起当时。',
        ),
      ));
      items.add(MemoryAlbumItem(
        itemId: 'photo_${photo.id}',
        itemType: 'photo_card',
        title: _photoTitle(photo),
        content: _photoContent(
          photo,
          familyById[photo.familyMemberId],
          memoryById[photo.memoryEventId],
          user,
        ),
        photoId: photo.id,
        relatedProfileFields: _photoRelatedFields(photo),
        familyQuestions: questions,
      ));
    }

    return MemoryAlbumChapter(
      chapterId: 'photo_memory',
      chapterTitle: '照片里的那一刻',
      chapterSubtitle: '先看见画面，再想起人和事',
      chapterIntro: '一张照片不用说得太满，先从画面里的人、地方和小物件慢慢讲。',
      chapterType: 'photo_memory',
      items: items,
    );
  }

  static MemoryAlbumChapter _buildDailyChapter(
    List<Map<String, dynamic>> dailyLifeRecords,
    Map<String, dynamic>? user,
  ) {
    final items = <MemoryAlbumItem>[];
    for (final row in dailyLifeRecords.take(8)) {
      final date = _text(row['date']);
      final parts = <String>[];
      void add(String label, String key) {
        final value = _text(row[key]);
        if (value.isNotEmpty) parts.add('$label$value');
      }

      add('早饭：', 'breakfast');
      add('午饭：', 'lunch');
      add('晚饭：', 'dinner');
      add('活动：', 'activities');
      add('见到的人：', 'people_met');
      add('去过的地方：', 'places_went');
      add('心情：', 'mood');
      if (parts.isEmpty) continue;
      items.add(MemoryAlbumItem(
        itemId: 'daily_${row['id'] ?? date}',
        itemType: 'text_card',
        title: date.isEmpty ? '一段日常' : date,
        content: parts.join('；'),
        relatedProfileFields: const ['daily_life_records'],
      ));
    }

    final food = _text(user?['food_preference']);
    if (food.isNotEmpty) {
      items.insert(
        0,
        MemoryAlbumItem(
          itemId: 'daily_food_preference',
          itemType: 'text_card',
          title: '熟悉的味道',
          content: '饮食习惯里记着：$food。这样的小细节，常常最有家的味道。',
          relatedProfileFields: const ['food_preference'],
        ),
      );
    }

    return MemoryAlbumChapter(
      chapterId: 'daily_life',
      chapterTitle: '日常里的安稳',
      chapterSubtitle: '饭菜、活动和心情也会留下痕迹',
      chapterIntro: '这些日常记录适合慢慢补，不需要一次写完整。',
      chapterType: 'daily_life',
      items: items,
    );
  }

  static List<MemoryTimelineEntry> _buildTimeline(
    List<Map<String, dynamic>> memoryEvents,
    List<ProfilePhotoModel> photos,
  ) {
    final entries = <MemoryTimelineEntry>[];
    for (final row in memoryEvents) {
      final title = _text(row['title']);
      final desc = _text(row['description']);
      if (title.isEmpty && desc.isEmpty) continue;
      entries.add(MemoryTimelineEntry(
        time: _text(row['event_time']),
        title: title.isEmpty ? '一段往事' : title,
        content: desc,
        relatedPhotoIds: _photoIdsForEvent(row, photos),
      ));
    }
    for (final photo
        in photos.where((photo) => _text(photo.photoTime).isNotEmpty)) {
      if (photo.memoryEventId != null) continue;
      entries.add(MemoryTimelineEntry(
        time: _text(photo.photoTime),
        title: _photoTitle(photo),
        content: _text(photo.caption),
        relatedPhotoIds: [photo.id],
      ));
    }
    return entries;
  }

  static List<ProfileItem> _profileItems(Map<String, dynamic>? user) {
    final items = <ProfileItem>[];
    void add(String label, String key) {
      final value = _text(user?[key]);
      if (value.isNotEmpty) {
        items.add(ProfileItem(label: label, value: value));
      }
    }

    add('姓名', 'name');
    add('性别', 'gender');
    add('出生年月/年龄', 'birth_year');
    add('籍贯', 'hometown');
    add('现居地', 'current_address');
    add('职业经历', 'career');
    add('兴趣爱好', 'hobbies');
    add('饮食习惯', 'food_preference');
    add('性格特点', 'personality');
    add('方言/说话习惯', 'dialect');
    return items;
  }

  static ProfilePhotoModel? _pickCoverPhoto(List<ProfilePhotoModel> photos) {
    if (photos.isEmpty) return null;
    final avatar =
        photos.where((photo) => photo.category == ProfilePhotoCategory.avatar);
    if (avatar.isNotEmpty) return avatar.first;
    final favorite = photos.where((photo) => photo.isFavorite);
    if (favorite.isNotEmpty) return favorite.first;
    return photos.first;
  }

  static String _albumSubtitle(
    Map<String, dynamic>? user,
    List<Map<String, dynamic>> familyMembers,
    List<Map<String, dynamic>> memoryEvents,
    List<ProfilePhotoModel> photos,
  ) {
    final parts = <String>[];
    final hometown = _text(user?['hometown']);
    if (hometown.isNotEmpty) parts.add(hometown);
    if (memoryEvents.isNotEmpty) parts.add('${memoryEvents.length}段经历');
    if (familyMembers.isNotEmpty) parts.add('${familyMembers.length}位亲友');
    if (photos.isNotEmpty) parts.add('${photos.length}张照片');
    return parts.isEmpty ? '慢慢翻看的回忆册' : parts.join(' · ');
  }

  static String _coverSubtitle(Map<String, dynamic>? user) {
    final birth = _text(user?['birth_year']);
    final hometown = _text(user?['hometown']);
    if (birth.isNotEmpty && hometown.isNotEmpty) {
      return '$birth · $hometown';
    }
    if (hometown.isNotEmpty) return hometown;
    if (birth.isNotEmpty) return birth;
    return '一本慢慢翻看的回忆册';
  }

  static String _coverText(
    String elderName,
    ProfilePhotoModel? coverPhoto,
    List<ProfilePhotoModel> photos,
  ) {
    if (coverPhoto == null) {
      return '先留一个安静的封面。等以后放上一张熟悉的照片，再从那一天慢慢讲起。';
    }
    final caption = _text(coverPhoto.caption);
    if (caption.isNotEmpty) {
      return caption;
    }
    return '先从这张照片开始。画面不用说得太满，家里人看见了，自然会想起那一天。';
  }

  static String _openingText(
    String elderName,
    List<Map<String, dynamic>> familyMembers,
    List<Map<String, dynamic>> memoryEvents,
    List<ProfilePhotoModel> photos,
  ) {
    final bits = <String>[
      '我们先从这些照片和家里记下的小事说起。',
      if (photos.isNotEmpty) '看到一张照片，就慢慢想起当时的地方、身边的人，还有那天的心情。',
      if (familyMembers.isNotEmpty) '家里人的名字也在这里，像平时聊天时那样轻轻提起。',
      if (memoryEvents.isNotEmpty) '那些重要的日子，我们一段一段慢慢翻。',
      '说不准的地方就先放着，等哪天想起来，再补上一句也好。',
    ];
    return bits.join('');
  }

  static String _elderProfileContent(
    String elderName,
    Map<String, dynamic>? user,
  ) {
    final hometown = _text(user?['hometown']);
    final personality = _text(user?['personality']);
    final hobbies = _text(user?['hobbies']);
    final parts = <String>['先记下这些熟悉的小信息。'];
    if (hometown.isNotEmpty) parts.add('籍贯写着$hometown。');
    if (personality.isNotEmpty) parts.add('性格特点可以记作“$personality”。');
    if (hobbies.isNotEmpty) parts.add('平时喜欢的事有：$hobbies。');
    parts.add('往后翻照片、讲故事时，这些小事会慢慢用得上。');
    return parts.join('');
  }

  static String _endingText(String elderName, List<String> missing) {
    if (missing.isEmpty) {
      return '今天先翻到这里。以后有新照片、新故事，再慢慢放进来。';
    }
    return '今天先翻到这里。还有一些地方可以慢慢想：${missing.join('、')}。不着急，想起一点，就添上一点。';
  }

  static String _photoTitle(ProfilePhotoModel photo) {
    final caption = _text(photo.caption);
    if (caption.isNotEmpty) return caption;
    final location = _text(photo.location);
    if (location.isNotEmpty) return '$location的一张照片';
    return switch (photo.category) {
      ProfilePhotoCategory.avatar => '一张头像照',
      ProfilePhotoCategory.family => '一张家庭照片',
      ProfilePhotoCategory.memory => '一张经历照片',
      ProfilePhotoCategory.daily => '一张日常照片',
      ProfilePhotoCategory.other => '一张照片',
    };
  }

  static String _photoContent(
    ProfilePhotoModel photo,
    Map<String, dynamic>? familyMember,
    Map<String, dynamic>? memoryEvent,
    Map<String, dynamic>? user,
  ) {
    final caption = _text(photo.caption);
    final time = _text(photo.photoTime);
    final location = _text(photo.location);
    final people = _text(photo.peopleInvolved);
    final name = _text(user?['name']);
    final hometown = _text(user?['hometown']);
    final parts = <String>[];

    if (caption.isNotEmpty) {
      parts.add(caption);
    } else {
      parts.add('这张照片还可以再多说几句。先看看画面里的人、地点，还有当时的心情。');
    }
    if (time.isNotEmpty || location.isNotEmpty) {
      parts.add([
        if (time.isNotEmpty) time,
        if (location.isNotEmpty) location,
      ].join('，'));
    }
    if (people.isNotEmpty) {
      parts.add('照片里标注的人物是：$people。');
    } else {
      parts.add('人物身份还没有完全确认时，先称作照片里的人，会更稳妥。');
    }
    if (familyMember != null) {
      final rel = _text(familyMember['relation']);
      final familyName = _text(familyMember['name']);
      if (familyName.isNotEmpty) {
        parts.add(rel.isEmpty ? '它和$familyName有关。' : '它和$rel$familyName有关。');
      }
    }
    if (memoryEvent != null) {
      final title = _text(memoryEvent['title']);
      if (title.isNotEmpty) parts.add('它也被关联到“$title”这段经历。');
    }
    if (name.isNotEmpty && hometown.isNotEmpty) {
      parts.add('$name来自$hometown，讲到这张照片时，可以把这份熟悉也轻轻带上。');
    }
    return parts.join(' ');
  }

  static List<String> _photoQuestions(ProfilePhotoModel photo) {
    final questions = <String>[];
    if (_text(photo.location).isEmpty) {
      questions.add('这张照片是在哪里拍的？');
    }
    if (_text(photo.photoTime).isEmpty) {
      questions.add('这张照片大概是哪一年或哪个季节拍的？');
    }
    if (_text(photo.peopleInvolved).isEmpty) {
      questions.add('照片里的人分别是谁？');
    }
    if (_text(photo.caption).isEmpty) {
      questions.add('拍这张照片时，家里人还记得发生过什么吗？');
    }
    return questions;
  }

  static List<String> _photoRelatedFields(ProfilePhotoModel photo) {
    final fields = <String>['profile_photos'];
    if (photo.familyMemberId != null) fields.add('family_members');
    if (photo.memoryEventId != null) fields.add('memory_events');
    return fields;
  }

  static List<FamilyQuestion> _dedupeQuestions(List<FamilyQuestion> questions) {
    final seen = <String>{};
    final out = <FamilyQuestion>[];
    for (final q in questions) {
      if (q.question.trim().isEmpty) continue;
      if (seen.add(q.question)) out.add(q);
    }
    return out;
  }

  static String _firstPhotoIdForEvent(
    Map<String, dynamic> event,
    List<ProfilePhotoModel> photos,
  ) {
    final ids = _photoIdsForEvent(event, photos);
    return ids.isEmpty ? '' : ids.first;
  }

  static List<String> _photoIdsForEvent(
    Map<String, dynamic> event,
    List<ProfilePhotoModel> photos,
  ) {
    final eventId = _int(event['id']);
    final paths = _decodeStringList(_text(event['photo_paths']));
    final ids = <String>[];
    for (final photo in photos) {
      if (eventId != null && photo.memoryEventId == eventId) {
        ids.add(photo.id);
      } else if (paths.contains(photo.filePath)) {
        ids.add(photo.id);
      }
    }
    return ids.toSet().toList();
  }

  static Map<String, dynamic> _familyInputRow(Map<String, dynamic> row) => {
        'name': _text(row['name']),
        'relation': _text(row['relation']),
        'birthday': _text(row['birthday']),
        'location': _text(row['location']),
        'contact_freq': _text(row['contact_freq']),
        'notes': _text(row['notes']),
        'photo_path': _text(row['photo_path']),
        'is_active': _bool01(row['is_active'], defaultValue: true),
      };

  static Map<String, dynamic> _memoryInputRow(Map<String, dynamic> row) => {
        'id': row['id'],
        'event_time': _text(row['event_time']),
        'title': _text(row['title']),
        'description': _text(row['description']),
        'location': _text(row['location']),
        'people_involved': _text(row['people_involved']),
        'emotion': _text(row['emotion']),
        'photo_paths': _decodeStringList(_text(row['photo_paths'])),
        'importance': _int(row['importance']) ?? 3,
        'verified': _bool01(row['verified'], defaultValue: false),
      };

  static Map<String, dynamic> _dailyInputRow(Map<String, dynamic> row) => {
        'date': _text(row['date']),
        'breakfast': _text(row['breakfast']),
        'lunch': _text(row['lunch']),
        'dinner': _text(row['dinner']),
        'activities': _text(row['activities']),
        'people_met': _text(row['people_met']),
        'places_went': _text(row['places_went']),
        'mood': _text(row['mood']),
      };

  static Map<String, dynamic> _photoInputRow(ProfilePhotoModel photo) => {
        'photo_id': photo.id,
        'category': _photoCategoryLabel(photo.category),
        'visible_content': _text(photo.caption).isEmpty
            ? '一张${_photoCategoryLabel(photo.category)}，画面细节还可以继续补充。'
            : _text(photo.caption),
        'people': _text(photo.peopleInvolved),
        'scene': _text(photo.location),
        'emotion': '',
        'objects': <String>[],
        'uncertain_points': [
          if (_text(photo.peopleInvolved).isEmpty) '人物身份未确认',
          if (_text(photo.caption).isEmpty) '照片内容说明不足',
        ],
        'photo_time': _text(photo.photoTime),
      };

  static List<String> _importantLabels(Map<String, dynamic>? user) {
    return [
      _text(user?['career']),
      _text(user?['hobbies']),
      _text(user?['personality']),
    ].where((text) => text.isNotEmpty).toList();
  }

  static String _mainCaregiver(List<Map<String, dynamic>> familyMembers) {
    for (final row in familyMembers) {
      final notes = _text(row['notes']);
      if (notes.contains('照护') ||
          notes.contains('照顾') ||
          notes.contains('主要')) {
        return _text(row['name']);
      }
    }
    return '';
  }

  static String _familyNotes(List<Map<String, dynamic>> familyMembers) {
    return familyMembers
        .map((row) => _text(row['notes']))
        .where((text) => text.isNotEmpty)
        .take(5)
        .join('；');
  }

  static List<String> _favoritePlaces(
    List<ProfilePhotoModel> photos,
    List<Map<String, dynamic>> memoryEvents,
  ) {
    final places = <String>{
      for (final photo in photos)
        if (_text(photo.location).isNotEmpty) _text(photo.location),
      for (final event in memoryEvents)
        if (_text(event['location']).isNotEmpty) _text(event['location']),
    };
    return places.toList();
  }

  static String _photoCategoryLabel(ProfilePhotoCategory category) {
    return switch (category) {
      ProfilePhotoCategory.avatar => '头像',
      ProfilePhotoCategory.family => '家庭照片',
      ProfilePhotoCategory.memory => '经历照片',
      ProfilePhotoCategory.daily => '日常照片',
      ProfilePhotoCategory.other => '其他',
    };
  }

  static bool _isSpouseRelation(String relation) {
    return relation.contains('老伴') ||
        relation.contains('配偶') ||
        relation.contains('丈夫') ||
        relation.contains('妻子');
  }

  static bool _isChildRelation(String relation) {
    return relation.contains('儿子') ||
        relation.contains('女儿') ||
        relation.contains('大儿') ||
        relation.contains('小儿') ||
        relation.contains('孩子');
  }

  static bool _isGrandchildRelation(String relation) {
    return relation.contains('孙') || relation.contains('外孙');
  }

  static List<String> _decodeStringList(String raw) {
    if (raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return raw
        .split(RegExp(r'[,，;；\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _bool01(Object? value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes' || text == '是') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == '否') {
      return false;
    }
    return defaultValue;
  }

  static String _text(Object? value) {
    final text = value?.toString().trim();
    return text ?? '';
  }
}
