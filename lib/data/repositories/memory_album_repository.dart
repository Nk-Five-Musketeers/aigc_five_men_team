import 'dart:convert';

import '../../core/narration/narration_text.dart';
import '../local_db/local_database.dart';
import '../models/memory_album.dart';
import '../models/profile_photo.dart';
import '../models/profile_video.dart';

part 'memory_album_composer.dart';

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
    final videos = await LocalDatabase.listProfileVideosForUser(ownerUserId);
    final imageOnlyPhotos = photos.where((photo) => !photo.isVideo).toList();
    final allMedia = [...imageOnlyPhotos, ..._photosFromVideos(videos)];

    final generationInput = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: ownerUserId,
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: allMedia,
    );
    final album = MemoryAlbumComposer.compose(
      ownerUserId: ownerUserId,
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: allMedia,
    );

    return MemoryAlbumDraft(
      album: album,
      photos: allMedia,
      generationInput: generationInput,
    );
  }

  static List<ProfilePhotoModel> _photosFromVideos(
    List<ProfileVideoModel> videos,
  ) {
    return videos
        .map(
          (video) => ProfilePhotoModel(
            id: video.id,
            ownerUserId: video.ownerUserId,
            filePath: video.filePath,
            category: ProfilePhotoCategory.memory,
            caption: video.caption,
            metadata: {
              'source': 'chat',
              'media_type': 'video',
              'message_id': video.messageId,
            },
            createdAt: video.createdAt,
          ),
        )
        .toList();
  }
}

class MemoryAlbumComposer {
  MemoryAlbumComposer._();

  static const String _audiobookPrompt = '''
你是一位温柔的回忆故事撰写者，正在为一位老人生成一份可以边看边听的回忆图鉴。
这份图鉴不是普通资料卡，也不是简历，而是一份适合被朗读出来的回忆故事。
语言要适合朗读，句子不要太长；每段最好控制在 2 到 4 句话，方便前端逐句高亮。
把姓名、籍贯、家庭关系、人生经历自然穿插进叙事里，每张照片都要成为一个故事入口。
文字要温暖、克制、真实，不要过度煽情；不要编造没有提供的事实，信息不足时少写，不要猜测。
章节之间要有过渡语，让整本图鉴听起来像一段连续的人生故事。
输出 JSON 需要包含 album_title、album_subtitle、opening、chapters、ending，并在每个 item 中给出 narration_text 与 sentences，供前端逐句朗读、高亮和自动跟随。
content 和 narration_text 必须是可以直接朗读的故事正文，不能出现写作指导、资料说明、补充提醒、占位提示或任何元叙述。
''';

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
        'mode': '听小说 / 有声书',
        'narration_prompt': _audiobookPrompt,
        'sentence_length': '句子不要太长，每段 2 到 4 句话',
        'frontend_support': [
          '逐句朗读',
          '当前句高亮',
          '自动滚动或翻页',
          '点击句子从该句开始',
        ],
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

    final familyChapter = _buildFamilyChapter(familyMembers, elderName);
    if (familyChapter.items.isNotEmpty) {
      chapters.add(familyChapter);
    }

    final lifeChapter = _buildLifeChapter(memoryEvents, photos, elderName);
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

    final dailyChapter = _buildDailyChapter(dailyLifeRecords, user, elderName);
    if (dailyChapter.items.isNotEmpty) {
      chapters.add(dailyChapter);
    }

    final timeline = _buildTimeline(memoryEvents, photos);
    final addedParts = chapters.map((chapter) => chapter.chapterTitle).toList();

    final album = MemoryAlbum(
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
        title: '故事还在继续',
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
      narration: const MemoryAlbumNarration(segments: <NarrationSegment>[]),
    );
    return album.copyWith(narration: buildAlbumNarration(album));
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
          if (career.isNotEmpty) '$elderName的岁月里，有一段和$career相连的日子。',
          if (hobbies.isNotEmpty) '平时的生活里，$hobbies是家人熟悉的爱好。',
          if (food.isNotEmpty) '餐桌上，$food是很容易被想起的味道。',
          if (personality.isNotEmpty) '家人记得$elderName的性格，常常会想到$personality。',
          if (dialect.isNotEmpty) '$elderName说话时带着$dialect，听起来很亲切。',
          if (care.isNotEmpty) '日常照看里，家人也一直记着$care。',
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
      chapterSubtitle: '家人记得的来处和日子',
      chapterIntro: '$elderName的故事，藏在家人记得的一件件小事里。',
      chapterType: 'profile',
      items: items,
    );
  }

  static MemoryAlbumChapter _buildFamilyChapter(
    List<Map<String, dynamic>> familyMembers,
    String elderName,
  ) {
    final items = <MemoryAlbumItem>[];
    for (final row in familyMembers.take(12)) {
      final name = _text(row['name']);
      if (name.isEmpty) continue;
      final relation = _text(row['relation']);
      final location = _text(row['location']);
      final contact = _text(row['contact_freq']);
      final notes = _text(row['notes']);
      items.add(MemoryAlbumItem(
        itemId: 'family_${row['id'] ?? name}',
        itemType: 'profile_card',
        title: relation.isEmpty ? name : '$relation · $name',
        content: [
          relation.isEmpty
              ? '$name在家人的记忆里有自己的位置。'
              : '$name是$elderName的$relation。',
          if (location.isNotEmpty) '$name如今常在$location。',
          if (contact.isNotEmpty) '家里和$name保持着$contact的联系。',
          if (notes.isNotEmpty) notes,
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
      chapterSubtitle: '名字背后都是牵挂',
      chapterIntro: '$elderName的日子里，家人的名字总是和牵挂连在一起。',
      chapterType: 'family',
      items: items,
    );
  }

  static MemoryAlbumChapter _buildLifeChapter(
    List<Map<String, dynamic>> memoryEvents,
    List<ProfilePhotoModel> photos,
    String elderName,
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
          if (time.isNotEmpty && title.isNotEmpty) '$time，$title。',
          if (time.isNotEmpty && title.isEmpty) '$time，家里记下了这一段往事。',
          if (time.isEmpty && title.isNotEmpty) '$title，是家里记下的一段往事。',
          if (location.isNotEmpty) '那段日子发生在$location。',
          if (desc.isNotEmpty) desc,
          if (people.isNotEmpty) '$people也在这段记忆里。',
          if (emotion.isNotEmpty) '那时留下的感受是$emotion。',
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
      chapterSubtitle: '那些被家人记住的时刻',
      chapterIntro: '$elderName走过的日子里，有些时刻一直被家人放在心上。',
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
          reason: '这些细节会让家人更容易想起当时。',
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

    final elderName = _text(user?['name']);
    return MemoryAlbumChapter(
      chapterId: 'photo_memory',
      chapterTitle: '照片里的那一刻',
      chapterSubtitle: '人、地方和那一天',
      chapterIntro: '这些照片留下了${elderName.isEmpty ? '家人' : elderName}生命里的一个个片刻。',
      chapterType: 'photo_memory',
      items: items,
    );
  }

  static MemoryAlbumChapter _buildDailyChapter(
    List<Map<String, dynamic>> dailyLifeRecords,
    Map<String, dynamic>? user,
    String elderName,
  ) {
    final items = <MemoryAlbumItem>[];
    for (final row in dailyLifeRecords.take(8)) {
      final date = _text(row['date']);
      final content = _dailyStory(row, date);
      if (content.isEmpty) continue;
      items.add(MemoryAlbumItem(
        itemId: 'daily_${row['id'] ?? date}',
        itemType: 'text_card',
        title: date.isEmpty ? '一段日常' : date,
        content: content,
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
          content: '家里人记得，$elderName喜欢$food。餐桌上的这个味道，是日子里很熟悉的一部分。',
          relatedProfileFields: const ['food_preference'],
        ),
      );
    }

    return MemoryAlbumChapter(
      chapterId: 'daily_life',
      chapterTitle: '日常里的安稳',
      chapterSubtitle: '饭菜、活动和心情也会留下痕迹',
      chapterIntro: '$elderName平常的日子，也有家人熟悉的安稳味道。',
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

  static String _dailyStory(Map<String, dynamic> row, String date) {
    final clauses = <String>[];
    void add(String sentence) {
      final text = _trimEndingPunctuation(sentence);
      if (text.isNotEmpty) clauses.add(text);
    }

    final breakfast = _text(row['breakfast']);
    final lunch = _text(row['lunch']);
    final dinner = _text(row['dinner']);
    final activities = _text(row['activities']);
    final people = _text(row['people_met']);
    final places = _text(row['places_went']);
    final mood = _text(row['mood']);

    if (breakfast.isNotEmpty) add('早饭吃的是$breakfast');
    if (lunch.isNotEmpty) add('午饭有$lunch');
    if (dinner.isNotEmpty) add('晚饭有$dinner');
    if (activities.isNotEmpty) add('那天做了$activities');
    if (people.isNotEmpty) add('见到了$people');
    if (places.isNotEmpty) add('去过$places');
    if (mood.isNotEmpty) add('心情是$mood');
    if (clauses.isEmpty) return '';

    final prefix = date.isEmpty ? '这一天' : date;
    return '$prefix，${clauses.join('，')}。';
  }

  static String _ensureSentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (RegExp(r'[。！？!?；;]$').hasMatch(trimmed)) return trimmed;
    return '$trimmed。';
  }

  static String _trimEndingPunctuation(String text) {
    return text.trim().replaceAll(RegExp(r'[。！？!?；;，,]+$'), '');
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
    final images = photos.where((photo) => !photo.isVideo).toList();
    if (images.isEmpty) return photos.first;
    final avatar =
        images.where((photo) => photo.category == ProfilePhotoCategory.avatar);
    if (avatar.isNotEmpty) return avatar.first;
    final favorite = images.where((photo) => photo.isFavorite);
    if (favorite.isNotEmpty) return favorite.first;
    return images.first;
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
      return '$elderName的故事，藏在家人记得的一件件小事里。';
    }
    final caption = _text(coverPhoto.caption);
    if (caption.isNotEmpty) {
      return _ensureSentence(caption);
    }
    final time = _text(coverPhoto.photoTime);
    final location = _text(coverPhoto.location);
    final people = _text(coverPhoto.peopleInvolved);
    final parts = <String>[
      if (time.isNotEmpty && location.isNotEmpty)
        '$time，$elderName在$location留下了这一刻。',
      if (time.isNotEmpty && location.isEmpty) '$time，$elderName留下了这一刻。',
      if (time.isEmpty && location.isNotEmpty) '$elderName在$location留下了这一刻。',
      if (people.isNotEmpty) '$people也在这个片刻里。',
    ];
    return parts.isEmpty ? '$elderName的故事，在家人的记忆里慢慢展开。' : parts.join('');
  }

  static String _openingText(
    String elderName,
    List<Map<String, dynamic>> familyMembers,
    List<Map<String, dynamic>> memoryEvents,
    List<ProfilePhotoModel> photos,
  ) {
    final bits = <String>[
      '这是$elderName的回忆，也是家人一起记住的日子。',
      if (familyMembers.isNotEmpty) '那些熟悉的名字，陪在$elderName的故事里。',
      if (memoryEvents.isNotEmpty) '那些被记下的时刻，一件件连成$elderName走过的路。',
      if (photos.isNotEmpty) '照片里的片刻，也留住了当时的人和地方。',
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
    final career = _text(user?['career']);
    final parts = <String>[
      if (hometown.isNotEmpty) '$elderName和$hometown有着熟悉的来处。',
      if (career.isNotEmpty) '$career的经历，也留在$elderName走过的岁月里。',
      if (personality.isNotEmpty) '家人眼里的$elderName，带着$personality的性格。',
      if (hobbies.isNotEmpty) '$hobbies是$elderName日子里常有的喜欢。',
    ];
    if (parts.isEmpty) {
      parts.add('$elderName的日子里，有许多家人熟悉的细节。');
    }
    return parts.join('');
  }

  static String _endingText(String elderName, List<String> missing) {
    return '$elderName的日子还在继续，家人的记挂也还在继续。';
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
    final elderName = _text(user?['name']);
    final parts = <String>[];

    if (caption.isNotEmpty) {
      parts.add(_ensureSentence(caption));
    }
    if (time.isNotEmpty || location.isNotEmpty) {
      if (time.isNotEmpty && location.isNotEmpty) {
        parts.add('$time，$location留下了这一刻。');
      } else if (time.isNotEmpty) {
        parts.add('$time，这一刻被家人留了下来。');
      } else {
        parts.add('$location留下了这一刻。');
      }
    }
    if (people.isNotEmpty) {
      parts.add('$people也在这一刻里。');
    }
    if (familyMember != null) {
      final rel = _text(familyMember['relation']);
      final familyName = _text(familyMember['name']);
      if (familyName.isNotEmpty) {
        if (rel.isNotEmpty && elderName.isNotEmpty) {
          parts.add('$familyName是$elderName的$rel，这份牵挂也留在这里。');
        } else {
          parts.add('$familyName也和这一刻连在一起。');
        }
      }
    }
    if (memoryEvent != null) {
      final title = _text(memoryEvent['title']);
      final desc = _text(memoryEvent['description']);
      if (desc.isNotEmpty && !parts.contains(desc)) {
        parts.add(_ensureSentence(desc));
      } else if (title.isNotEmpty) {
        parts.add('“$title”那段日子，也留在这里。');
      }
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
        'media_type': photo.isVideo ? 'video' : 'image',
        'visible_content': _photoVisibleContent(photo),
        'people': _text(photo.peopleInvolved),
        'scene': _text(photo.location),
        'emotion': '',
        'objects': <String>[],
        'uncertain_points': [
          if (_text(photo.peopleInvolved).isEmpty) '缺少人物信息',
          if (_text(photo.caption).isEmpty) '缺少照片说明',
        ],
        'photo_time': _text(photo.photoTime),
      };

  static String _photoVisibleContent(ProfilePhotoModel photo) {
    final caption = _text(photo.caption);
    if (caption.isNotEmpty) {
      return photo.isVideo ? '视频：$caption' : caption;
    }
    if (photo.isVideo) return '一段家庭视频';
    return [
      _text(photo.photoTime),
      _text(photo.location),
      _text(photo.peopleInvolved),
    ].where((text) => text.isNotEmpty).join('，');
  }

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
        return decoded.map(_text).where((item) => item.isNotEmpty).toList();
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
    if (text == null || text.isEmpty) return '';
    return _isNoInformationText(text) ? '' : text;
  }

  static bool _isNoInformationText(String text) {
    final normalized = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s　。.!！?？,，;；:：、~～_—\-]+'), '');
    if (normalized.isEmpty) return true;

    const exactNoInfo = <String>{
      '无',
      '暂无',
      '没有',
      '没',
      '否',
      '不',
      '不用',
      '无需',
      '无事',
      '没事',
      '不详',
      '未知',
      '不知道',
      '不清楚',
      '未填写',
      '未填',
      '未确认',
      '待确认',
      '未说明',
      '未提供',
      '空',
      'null',
      'none',
      'nil',
      'na',
      'n/a',
      'no',
      'nothing',
    };
    if (exactNoInfo.contains(normalized)) return true;

    const noInfoPhrases = <String>[
      '无特殊',
      '无特别',
      '没有特殊',
      '没有特别',
      '暂无特殊',
      '暂无特别',
      '无需特殊',
      '不需要特殊',
      '不用特殊',
      '无注意',
      '无注意事项',
      '没有注意事项',
      '暂无注意事项',
      '无照看',
      '无照护',
      '无护理',
      '无要求',
      '没有要求',
      '暂无要求',
      '无备注',
      '没有备注',
      '暂无备注',
      '无补充',
      '没有补充',
      '暂无补充',
    ];
    return noInfoPhrases.any(normalized.startsWith);
  }
}
