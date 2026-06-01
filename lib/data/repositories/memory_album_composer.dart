part of 'memory_album_repository.dart';

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
    final albumPhotos = dedupePhotosByStoryContent(photos);
    final qualityWarnings = _collectQualityWarnings(
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: albumPhotos,
    );
    final children = familyMembers
        .where(
            (row) => _isChildRelation(_fieldText('relation', row['relation'])))
        .map(_familyInputRow)
        .toList();
    final grandchildren = familyMembers
        .where((row) =>
            _isGrandchildRelation(_fieldText('relation', row['relation'])))
        .map(_familyInputRow)
        .toList();
    final spouse = familyMembers.firstWhere(
      (row) => _isSpouseRelation(_fieldText('relation', row['relation'])),
      orElse: () => const <String, dynamic>{},
    );

    return {
      'existing_memory_album': {
        'album_title': '未命名',
        'chapters': <dynamic>[],
        'photo_cards': <dynamic>[],
      },
      'elder_profile': {
        'name': _userText(user, 'name'),
        'gender': _userText(user, 'gender'),
        'birth_year_or_age': _userText(user, 'birth_year'),
        'hometown': _userText(user, 'hometown'),
        'current_location': _userText(user, 'current_address'),
        'personality': _userText(user, 'personality'),
        'hobbies': _userText(user, 'hobbies'),
        'common_words': _userText(user, 'dialect'),
        'important_labels': _importantLabels(user),
      },
      'family_profile': {
        'spouse': _fieldText('name', spouse['name']),
        'children': children,
        'grandchildren': grandchildren,
        'main_caregiver': _mainCaregiver(familyMembers),
        'family_relationship_notes': _familyNotes(familyMembers),
        'members': familyMembers.map(_familyInputRow).toList(),
      },
      'life_experience': {
        'education': '',
        'work': _userText(user, 'career'),
        'important_events': memoryEvents.map(_memoryInputRow).toList(),
        'memorable_stories': memoryEvents
            .map((row) => _fieldText('description', row['description']))
            .where((text) => text.isNotEmpty)
            .toList(),
        'family_stories': familyMembers
            .map((row) => _fieldText('notes', row['notes']))
            .where((text) => text.isNotEmpty)
            .toList(),
      },
      'daily_life_info': {
        'daily_habits': dailyLifeRecords.map(_dailyInputRow).toList(),
        'favorite_food': _userText(user, 'food_preference'),
        'favorite_places': _favoritePlaces(albumPhotos, memoryEvents),
        'objects_often_used': <String>[],
        'health_or_care_notes': [
          _userText(user, 'care_notes'),
          _userText(user, 'medical_notes'),
        ].where((text) => text.isNotEmpty).join('；'),
      },
      'photo_analysis_results':
          albumPhotos.map((photo) => _photoInputRow(photo)).toList(),
      'family_notes': albumPhotos
          .where((photo) => _fieldText('caption', photo.caption).isNotEmpty)
          .map((photo) => {
                'photo_id': photo.id,
                'note': _fieldText('caption', photo.caption),
              })
          .toList(),
      'input_quality_warnings': qualityWarnings,
      'generation_requirements': {
        'tone': '温暖、自然、娓娓道来',
        'target_reader': '老人本人和家属',
        'length': '中等',
        'mode': '听小说 / 有声书',
        'narration_prompt': MemoryAlbumPrompts.albumGenerationPrompt,
        'sentence_length': '句子不要太长，每段 2 到 4 句话',
        'frontend_support': [
          '逐句朗读',
          '当前句高亮',
          '自动滚动或翻页',
          '点击句子从该句开始',
        ],
        'allow_rebuild_album': true,
        'invalid_input_policy':
            '遇到字段套话、占位话、明显不合理或太泛的信息，不要写进正文；能提取真实细节则只保留真实细节，不能提取则少写，并在 notes/possible_conflicts 中提示家属补充。',
        'output_language': '中文',
        'source': 'local_pre_entry',
        'owner_user_id': ownerUserId,
      },
    };
  }

  static List<ProfilePhotoModel> dedupePhotosByStoryContent(
    List<ProfilePhotoModel> photos,
  ) {
    final buckets = <String, ProfilePhotoModel>{};
    final looseBuckets = <String, ProfilePhotoModel>{};
    for (final photo in photos) {
      final key = _photoDuplicateKey(photo);
      final looseKey = _photoLooseDuplicateKey(photo);
      final existing = key.isEmpty ? null : buckets[key];
      if (existing != null) {
        final preferred = _preferPhoto(existing, photo);
        buckets[key] = preferred;
        if (looseKey.isNotEmpty) looseBuckets[looseKey] = preferred;
        continue;
      }

      final looseExisting = looseKey.isEmpty ? null : looseBuckets[looseKey];
      if (looseExisting != null) {
        final preferred = _preferPhoto(looseExisting, photo);
        final oldKey = _photoDuplicateKey(looseExisting);
        final newKey = _photoDuplicateKey(photo);
        if (oldKey.isNotEmpty) buckets[oldKey] = preferred;
        if (newKey.isNotEmpty) buckets[newKey] = preferred;
        looseBuckets[looseKey] = preferred;
        continue;
      }

      if (key.isNotEmpty) buckets[key] = photo;
      if (looseKey.isNotEmpty) looseBuckets[looseKey] = photo;
      if (key.isEmpty && looseKey.isEmpty) {
        buckets['id:${photo.id}'] = photo;
      }
    }

    final keptIds = <String>{};
    final kept = <ProfilePhotoModel>[];
    for (final photo in photos) {
      final key = _photoDuplicateKey(photo);
      final looseKey = _photoLooseDuplicateKey(photo);
      final representative = key.isNotEmpty
          ? buckets[key]
          : looseKey.isNotEmpty
              ? looseBuckets[looseKey]
              : buckets['id:${photo.id}'];
      if (representative == null) continue;
      if (representative.id != photo.id) continue;
      if (keptIds.add(photo.id)) kept.add(photo);
    }
    return kept;
  }

  static String _photoDuplicateKey(ProfilePhotoModel photo) {
    final metadataKey = _photoMetadataDuplicateKey(photo);
    if (metadataKey.isNotEmpty) return metadataKey;

    final path = _normalizePath(photo.filePath);
    if (path.isNotEmpty) return 'path:$path';

    final facts = [
      _fieldText('caption', photo.caption),
      _fieldText('photo_time', photo.photoTime),
      _fieldText('location', photo.location),
      _fieldText('people_involved', photo.peopleInvolved),
      if (photo.memoryEventId != null) 'event:${photo.memoryEventId}',
      if (photo.familyMemberId != null) 'family:${photo.familyMemberId}',
      photo.category.value,
    ].map(_normalizeForQuality).where((text) => text.isNotEmpty).toList();
    if (facts.length < 2) return '';
    return 'story:${facts.join('|')}';
  }

  static String _photoLooseDuplicateKey(ProfilePhotoModel photo) {
    final caption = _normalizeForQuality(_fieldText('caption', photo.caption));
    final people = _normalizeForQuality(
        _fieldText('people_involved', photo.peopleInvolved));
    final location =
        _normalizeForQuality(_fieldText('location', photo.location));
    final time =
        _normalizeForQuality(_fieldText('photo_time', photo.photoTime));
    final event =
        photo.memoryEventId == null ? '' : 'event:${photo.memoryEventId}';

    if (caption.isNotEmpty && event.isNotEmpty) {
      return 'caption_event:$caption|$event';
    }
    if (caption.isNotEmpty && people.isNotEmpty && location.isNotEmpty) {
      return 'caption_people_location:$caption|$people|$location';
    }
    if (caption.isNotEmpty && time.isNotEmpty && location.isNotEmpty) {
      return 'caption_time_location:$caption|$time|$location';
    }
    if (caption.length >= 8 && people.isNotEmpty) {
      return 'caption_people:$caption|$people';
    }
    return '';
  }

  static String _photoMetadataDuplicateKey(ProfilePhotoModel photo) {
    final metadata = photo.metadata;
    if (metadata == null || metadata.isEmpty) return '';
    const keys = [
      'perceptual_hash',
      'phash',
      'image_hash',
      'content_hash',
      'sha256',
      'md5',
      'asset_id',
      'original_asset_id',
    ];
    for (final key in keys) {
      final value = metadata[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && !_isNoInformationText(value)) {
        return 'meta:$key:${_normalizeForQuality(value)}';
      }
    }
    return '';
  }

  static ProfilePhotoModel _preferPhoto(
    ProfilePhotoModel a,
    ProfilePhotoModel b,
  ) {
    final scoreA = _photoKeepScore(a);
    final scoreB = _photoKeepScore(b);
    if (scoreA != scoreB) return scoreB > scoreA ? b : a;
    return b.createdAt.isBefore(a.createdAt) ? b : a;
  }

  static int _photoKeepScore(ProfilePhotoModel photo) {
    var score = 0;
    if (photo.isFavorite) score += 100;
    if (!photo.isVideo) score += 20;
    if (_fieldText('caption', photo.caption).isNotEmpty) score += 16;
    if (_fieldText('people_involved', photo.peopleInvolved).isNotEmpty) {
      score += 12;
    }
    if (_fieldText('location', photo.location).isNotEmpty) score += 10;
    if (_fieldText('photo_time', photo.photoTime).isNotEmpty) score += 8;
    if (photo.memoryEventId != null) score += 6;
    if (photo.familyMemberId != null) score += 4;
    return score;
  }

  static String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll('\\', '/').toLowerCase();
  }

  static List<Map<String, String>> storyKeywordsForInput(
    Map<String, dynamic> generationInput,
  ) {
    final out = <Map<String, String>>[];
    final seen = <String>{};

    void addKeyword(
      String source,
      String label,
      Object? value, {
      String refId = '',
    }) {
      if (value is Iterable && value is! String) {
        for (final item in value) {
          addKeyword(source, label, item, refId: refId);
        }
        return;
      }
      final text = _trimEndingPunctuation(value?.toString() ?? '').trim();
      if (text.isEmpty || _isNoInformationText(text)) return;
      final normalized = _normalizeForQuality(text);
      if (normalized.isEmpty || _isGenericKeyword(normalized)) return;
      final storyKey = _storyFactKey(text);
      if (!seen.add(storyKey.isEmpty ? normalized : storyKey)) return;
      out.add({
        'source': source,
        'label': label,
        'value': text.length > 80 ? '${text.substring(0, 80)}…' : text,
        if (refId.isNotEmpty) 'ref_id': refId,
      });
    }

    final elder = _inputMap(generationInput['elder_profile']);
    const elderLabels = {
      'name': '姓名',
      'gender': '性别',
      'birth_year_or_age': '出生年月/年龄',
      'hometown': '籍贯',
      'current_location': '现居地',
      'personality': '性格特点',
      'hobbies': '兴趣爱好',
      'common_words': '方言/说话习惯',
      'important_labels': '重要标签',
    };
    for (final entry in elderLabels.entries) {
      addKeyword('elder_profile', entry.value, elder[entry.key]);
    }

    final family = _inputMap(generationInput['family_profile']);
    addKeyword('family_profile', '老伴', family['spouse']);
    addKeyword('family_profile', '主要照看人', family['main_caregiver']);
    addKeyword(
      'family_profile',
      '家人补充',
      family['family_relationship_notes'],
    );
    for (final member in _inputMaps(family['members']).take(20)) {
      final name = member['name']?.toString().trim() ?? '';
      final refId = name.isEmpty ? '' : 'family:$name';
      addKeyword('family_member', '亲属姓名', member['name'], refId: refId);
      addKeyword('family_member', '亲属关系', member['relation'], refId: refId);
      addKeyword('family_member', '所在地', member['location'], refId: refId);
      addKeyword(
        'family_member',
        '联系频率',
        member['contact_freq'],
        refId: refId,
      );
      addKeyword('family_member', '备注', member['notes'], refId: refId);
    }

    final life = _inputMap(generationInput['life_experience']);
    addKeyword('life_experience', '职业经历', life['work']);
    for (final event in _inputMaps(life['important_events']).take(20)) {
      final refId = 'event:${event['id'] ?? out.length}';
      addKeyword('memory_event', '时间', event['event_time'], refId: refId);
      addKeyword('memory_event', '标题', event['title'], refId: refId);
      addKeyword('memory_event', '描述', event['description'], refId: refId);
      addKeyword('memory_event', '地点', event['location'], refId: refId);
      addKeyword(
        'memory_event',
        '相关人物',
        event['people_involved'],
        refId: refId,
      );
      addKeyword('memory_event', '感受', event['emotion'], refId: refId);
    }
    addKeyword('life_experience', '家族故事', life['family_stories']);

    final daily = _inputMap(generationInput['daily_life_info']);
    addKeyword('daily_life', '喜欢的味道', daily['favorite_food']);
    addKeyword('daily_life', '常去的地方', daily['favorite_places']);
    for (final record in _inputMaps(daily['daily_habits']).take(12)) {
      final refId = 'daily:${record['date'] ?? out.length}';
      addKeyword('daily_life', '日期', record['date'], refId: refId);
      addKeyword('daily_life', '早饭', record['breakfast'], refId: refId);
      addKeyword('daily_life', '午饭', record['lunch'], refId: refId);
      addKeyword('daily_life', '晚饭', record['dinner'], refId: refId);
      addKeyword('daily_life', '活动', record['activities'], refId: refId);
      addKeyword('daily_life', '见到的人', record['people_met'], refId: refId);
      addKeyword('daily_life', '去过的地方', record['places_went'], refId: refId);
      addKeyword('daily_life', '心情', record['mood'], refId: refId);
    }

    for (final photo
        in _inputMaps(generationInput['photo_analysis_results']).take(24)) {
      final refId = 'photo:${photo['photo_id'] ?? out.length}';
      addKeyword('photo', '照片内容', photo['visible_content'], refId: refId);
      addKeyword('photo', '人物', photo['people'], refId: refId);
      addKeyword('photo', '地点', photo['scene'], refId: refId);
      addKeyword('photo', '时间', photo['photo_time'], refId: refId);
    }
    for (final note in _inputMaps(generationInput['family_notes']).take(24)) {
      addKeyword(
        'family_note',
        '照片说明',
        note['note'],
        refId: 'photo:${note['photo_id'] ?? out.length}',
      );
    }

    return out.take(90).toList();
  }

  static MemoryAlbum compose({
    required String ownerUserId,
    required Map<String, dynamic>? user,
    required List<Map<String, dynamic>> familyMembers,
    required List<Map<String, dynamic>> memoryEvents,
    required List<Map<String, dynamic>> dailyLifeRecords,
    required List<ProfilePhotoModel> photos,
  }) {
    final albumPhotos = dedupePhotosByStoryContent(photos);
    final qualityWarnings = _collectQualityWarnings(
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: albumPhotos,
    );
    final name = _userText(user, 'name');
    final elderName = name.isEmpty ? '家里的长辈' : name;
    final profileItems = _profileItems(user);
    final coverPhoto = _pickCoverPhoto(albumPhotos);
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
    if (albumPhotos.isEmpty) {
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

    final lifeChapter = _buildLifeChapter(memoryEvents, albumPhotos, elderName);
    if (lifeChapter.items.isNotEmpty) {
      chapters.add(lifeChapter);
    }

    final photoChapter = _buildPhotoChapter(
      photos: albumPhotos,
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

    final timeline = _buildTimeline(memoryEvents, albumPhotos);
    final addedParts = chapters.map((chapter) => chapter.chapterTitle).toList();

    final album = MemoryAlbum(
      albumId: 'album_$ownerUserId',
      albumTitle: '$elderName的回忆图鉴',
      albumSubtitle:
          _albumSubtitle(user, familyMembers, memoryEvents, albumPhotos),
      cover: AlbumCover(
        title: elderName,
        subtitle: _coverSubtitle(user),
        coverText: _coverText(elderName, coverPhoto, albumPhotos),
        recommendedCoverPhotoId: coverPhoto?.id ?? '',
      ),
      opening: AlbumText(
        title: '慢慢翻',
        content:
            _openingText(elderName, familyMembers, memoryEvents, albumPhotos),
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
        possibleConflicts: qualityWarnings,
        missingInformation: missing,
      ),
      narration: const MemoryAlbumNarration(segments: <NarrationSegment>[]),
    );
    return dedupeRepeatedNarrationFacts(
      album.copyWith(narration: buildAlbumNarration(album)),
    );
  }

  static MemoryAlbum dedupeRepeatedNarrationFacts(MemoryAlbum album) {
    final seenFacts = <String>{};
    final report = _DuplicateFactReport();

    String cleanParagraph(String content) {
      return _dedupeRepeatedFactSentences(content, seenFacts, report);
    }

    final chapters = album.chapters.map((chapter) {
      final items = <MemoryAlbumItem>[];
      for (final item in chapter.items) {
        final cleanedContent = cleanParagraph(item.content);
        final titleFact = _storyFactKey(item.title);
        if (cleanedContent.isEmpty &&
            titleFact.isNotEmpty &&
            seenFacts.contains(titleFact)) {
          report.removedItems += 1;
          continue;
        }
        items.add(item.copyWith(content: cleanedContent));
      }
      return chapter.copyWith(
        chapterIntro: cleanParagraph(chapter.chapterIntro),
        items: items,
      );
    }).toList();

    final reviewed = album.copyWith(
      cover: album.cover
          .copyWith(coverText: cleanParagraph(album.cover.coverText)),
      opening: album.opening
          .copyWith(content: cleanParagraph(album.opening.content)),
      elderProfileCard: album.elderProfileCard.copyWith(
        content: cleanParagraph(album.elderProfileCard.content),
      ),
      chapters: chapters,
      ending:
          album.ending.copyWith(content: cleanParagraph(album.ending.content)),
      notes: report.changed
          ? album.notes.copyWith(
              rewrittenParts: _dedupeStrings([
                ...album.notes.rewrittenParts,
                '已自动合并 ${report.totalRemoved} 处重复故事内容',
              ]),
            )
          : album.notes,
      narration: const MemoryAlbumNarration(segments: <NarrationSegment>[]),
    );
    return reviewed.copyWith(narration: buildAlbumNarration(reviewed));
  }

  static String _dedupeRepeatedFactSentences(
    String content,
    Set<String> seenFacts,
    _DuplicateFactReport report,
  ) {
    final sentences = splitNarrationSentences(content);
    if (sentences.isEmpty) return content.trim();
    final kept = <String>[];
    for (final sentence in sentences) {
      final factKey = _storyFactKey(sentence);
      if (factKey.isNotEmpty && seenFacts.contains(factKey)) {
        report.removedSentences += 1;
        continue;
      }
      if (factKey.isNotEmpty) seenFacts.add(factKey);
      kept.add(_ensureSentence(sentence));
    }
    return kept.join();
  }

  static String _storyFactKey(String text) {
    final normalized = _normalizeForQuality(text);
    if (normalized.length < 6) return '';

    final teacher = RegExp(r'([\u4e00-\u9fa5]{1,6}老师)').firstMatch(normalized);
    if (teacher != null &&
        (normalized.contains('听') ||
            normalized.contains('讲课') ||
            normalized.contains('上课') ||
            normalized.contains('授课')) &&
        (normalized.contains('课') || normalized.contains('讲'))) {
      return 'listen_teacher:${teacher.group(1)}';
    }

    const exactFacts = [
      '骑马与砍杀',
      '听戏',
      '散步',
    ];
    for (final fact in exactFacts) {
      final key = _normalizeForQuality(fact);
      if (normalized.contains(key)) return 'fact:$key';
    }

    final compact = normalized.replaceAll(
      RegExp(
        r'我们|记得|你|也|曾经|家里人|这件事|那件事|那些|这个|那个|时候|日子|平常|平时|喜欢|爱|常常|总是|一起|慢慢|留下|留在|记忆里|熟悉|一点|自己的|小世界|后来|想起|认真|生活|片刻|瞬间',
      ),
      '',
    );
    if (compact.length >= 10 && compact.length <= 22) {
      return 'core:$compact';
    }
    return '';
  }

  static MemoryAlbumChapter _buildProfileChapter(
    String elderName,
    Map<String, dynamic>? user,
  ) {
    final items = <MemoryAlbumItem>[];
    final career = _userText(user, 'career');
    final hobbies = _userText(user, 'hobbies');
    final food = _userText(user, 'food_preference');
    final personality = _userText(user, 'personality');
    final dialect = _userText(user, 'dialect');

    if ([career, hobbies, food, personality, dialect]
        .any((text) => text.isNotEmpty)) {
      items.add(MemoryAlbumItem(
        itemId: 'profile_overview',
        itemType: 'text_card',
        title: '我们记得的你',
        content: [
          if (career.isNotEmpty) _careerStory(career),
          if (hobbies.isNotEmpty) _hobbyStory(hobbies),
          if (food.isNotEmpty) _foodStory(food),
          if (personality.isNotEmpty) _personalityStory(personality),
          if (dialect.isNotEmpty) '我们记得，你说话时带着$dialect，听起来亲切，也让家里人觉得熟悉。',
        ].join(' '),
        relatedProfileFields: const [
          'career',
          'hobbies',
          'food_preference',
          'personality',
          'dialect',
        ],
      ));
    }

    return MemoryAlbumChapter(
      chapterId: 'profile',
      chapterTitle: '家里人记得的你',
      chapterSubtitle: '那些藏在日子里的小事',
      chapterIntro: '我们想先从最熟悉的你讲起。不是资料里的几行字，而是家里人一想起来，就觉得亲近的那些片刻。',
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
      final name = _fieldText('name', row['name']);
      if (name.isEmpty) continue;
      final relation = _fieldText('relation', row['relation']);
      final location = _fieldText('location', row['location']);
      final contact = _fieldText('contact_freq', row['contact_freq']);
      final notes = _fieldText('notes', row['notes']);
      items.add(MemoryAlbumItem(
        itemId: 'family_${row['id'] ?? name}',
        itemType: 'profile_card',
        title: relation.isEmpty ? name : '$relation · $name',
        content: [
          relation.isEmpty
              ? '我们也记得，$name一直在家人的故事里有自己的位置。'
              : '我们也记得，$name是你的$relation。',
          if (location.isNotEmpty) '$name如今常在$location。',
          if (contact.isNotEmpty) '家里和$name保持着$contact的联系，这份牵挂也常常被提起。',
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
      chapterIntro: '说起你，很多名字也会跟着浮上来。那些称呼里，有家人的陪伴，也有平常日子里的牵挂。',
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
      final title = _fieldText('title', row['title']);
      final desc = _fieldText('description', row['description']);
      if (title.isEmpty && desc.isEmpty) continue;
      final time = _fieldText('event_time', row['event_time']);
      final location = _fieldText('location', row['location']);
      final people = _fieldText('people_involved', row['people_involved']);
      final emotion = _fieldText('emotion', row['emotion']);
      items.add(MemoryAlbumItem(
        itemId: 'life_${row['id'] ?? items.length}',
        itemType: 'timeline_card',
        title: title.isEmpty ? '一段往事' : title,
        content: [
          if (time.isNotEmpty && title.isNotEmpty) '我们记得，$time，家里人提起过$title。',
          if (time.isNotEmpty && title.isEmpty) '我们记得，$time，家里人留下了这一段往事。',
          if (time.isEmpty && title.isNotEmpty) '我们记得，$title背后，有家里人留下的一段往事。',
          if (location.isNotEmpty) '那段日子和$location有关。',
          if (desc.isNotEmpty) desc,
          if (people.isNotEmpty) '$people也在这段记忆里，让当时的场景又轻轻近了一点。',
          if (emotion.isNotEmpty) '后来再想起它，$emotion这样的感受也留了下来。',
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
      chapterIntro: '有些日子过去很久，家里人还是会记得。我们把这些片段放在这里，慢慢讲给你听。',
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

    return MemoryAlbumChapter(
      chapterId: 'photo_memory',
      chapterTitle: '照片里的那一刻',
      chapterSubtitle: '人、地方和那一天',
      chapterIntro: '有些照片看起来很普通，可我们知道，里面藏着家里人才懂的瞬间。',
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
      final date = _fieldText('date', row['date']);
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

    final food = _userText(user, 'food_preference');
    if (food.isNotEmpty) {
      items.insert(
        0,
        MemoryAlbumItem(
          itemId: 'daily_food_preference',
          itemType: 'text_card',
          title: '熟悉的味道',
          content: _foodStory(food),
          relatedProfileFields: const ['food_preference'],
        ),
      );
    }

    return MemoryAlbumChapter(
      chapterId: 'daily_life',
      chapterTitle: '日常里的安稳',
      chapterSubtitle: '饭菜、活动和心情也会留下痕迹',
      chapterIntro: '日子真正让人记住的，常常不是大事。饭桌上的味道、散步时的路、一天里的小心情，都能慢慢变成回忆。',
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
      final title = _fieldText('title', row['title']);
      final desc = _fieldText('description', row['description']);
      if (title.isEmpty && desc.isEmpty) continue;
      entries.add(MemoryTimelineEntry(
        time: _fieldText('event_time', row['event_time']),
        title: title.isEmpty ? '一段往事' : title,
        content: desc,
        relatedPhotoIds: _photoIdsForEvent(row, photos),
      ));
    }
    for (final photo in photos.where(
        (photo) => _fieldText('photo_time', photo.photoTime).isNotEmpty)) {
      if (photo.memoryEventId != null) continue;
      entries.add(MemoryTimelineEntry(
        time: _fieldText('photo_time', photo.photoTime),
        title: _photoTitle(photo),
        content: _fieldText('caption', photo.caption),
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

    final breakfast = _fieldText('breakfast', row['breakfast']);
    final lunch = _fieldText('lunch', row['lunch']);
    final dinner = _fieldText('dinner', row['dinner']);
    final activities = _fieldText('activities', row['activities']);
    final people = _fieldText('people_met', row['people_met']);
    final places = _fieldText('places_went', row['places_went']);
    final mood = _fieldText('mood', row['mood']);

    if (breakfast.isNotEmpty) add('早饭吃了$breakfast');
    if (lunch.isNotEmpty) add('午饭有$lunch');
    if (dinner.isNotEmpty) add('晚饭也有$dinner');
    if (activities.isNotEmpty) add('那天你做了$activities');
    if (people.isNotEmpty) add('也见到了$people');
    if (places.isNotEmpty) add('还去过$places');
    if (mood.isNotEmpty) add('那天的心情是$mood');
    if (clauses.isEmpty) return '';

    final prefix = date.isEmpty ? '这一天' : date;
    return '$prefix，${clauses.join('，')}。';
  }

  static String _careerStory(String career) {
    final lower = career.toLowerCase();
    if (career.contains('讲师') ||
        career.contains('教授') ||
        career.contains('教师') ||
        career.contains('老师')) {
      return '我们记得，你做$career的时候，曾经站在讲台上，把许多知识慢慢讲给别人听。那段和课堂相伴的日子，也留下了你认真生活的痕迹。';
    }
    if (career.contains('医生') || career.contains('护士')) {
      return '我们记得，你曾经把许多时间交给需要照顾的人。那样的日子不一定轻松，却能看见你的认真和耐心。';
    }
    if (career.contains('工人') ||
        career.contains('厂') ||
        career.contains('车间')) {
      return '我们记得，你曾经在忙碌的工作里，把日子一点点撑起来。那些踏实做事的年头，也留在家里人的记忆里。';
    }
    if (lower.contains('it') ||
        career.contains('工程') ||
        career.contains('技术')) {
      return '我们记得，你曾经和技术、项目、问题打交道。很多看起来安静的努力，其实都藏着认真生活的劲头。';
    }
    return '我们记得，你曾经把很多日子交给$career。那些经历不只是一个职业名称，也是一段认真走过的生活。';
  }

  static String _hobbyStory(String hobbies) {
    if (hobbies.contains('骑马与砍杀') || hobbies.toLowerCase().contains('game')) {
      return '闲下来的时候，你也有自己的小世界。比如打开游戏，沉进一段刀光剑影的故事里，让平常的日子多一点只有自己懂的乐趣。';
    }
    if (hobbies.contains('戏') || hobbies.contains('曲')) {
      return '我们也记得，你喜欢$hobbies。熟悉的唱腔一响起来，日子好像也跟着慢了下来。';
    }
    if (hobbies.contains('散步')) {
      return '我们也记得，你喜欢出去走走。脚步慢下来时，平常的路也会变成一天里安稳的一段。';
    }
    return '闲下来的时候，你也有自己的喜欢。$hobbies这件事，像是给平常日子留了一点只属于你的乐趣。';
  }

  static String _foodStory(String food) {
    if (RegExp(r'^(爱吃|喜欢吃|爱喝|喜欢喝)').hasMatch(food)) {
      return '家里人也记得，你$food。饭桌上的这些小习惯，有时比一句正式介绍更能让人想起你。';
    }
    return '家里人也记得你喜欢的味道。饭桌上的$food，有时比一句正式介绍更能让人想起你。';
  }

  static String _personalityStory(String personality) {
    if (_hasDirectNegativePersonality(personality)) {
      return '我们也记得，你是个性子很直的人。遇到在意的事，你有时会着急，可我们知道，那背后也是认真和在乎。';
    }
    return '我们也记得你身上$personality的一面。很多时候，这些细小的脾性，比正式的介绍更像家里人熟悉的你。';
  }

  static bool _hasDirectNegativePersonality(String text) {
    return text.contains('脾气暴') ||
        text.contains('暴躁') ||
        text.contains('固执') ||
        text.contains('倔') ||
        text.contains('急躁') ||
        text.contains('不好相处');
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
      final value = _userText(user, key);
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
    final hometown = _userText(user, 'hometown');
    if (hometown.isNotEmpty) parts.add(hometown);
    if (memoryEvents.isNotEmpty) parts.add('${memoryEvents.length}段经历');
    if (familyMembers.isNotEmpty) parts.add('${familyMembers.length}位亲友');
    if (photos.isNotEmpty) parts.add('${photos.length}张照片');
    return parts.isEmpty ? '慢慢翻看的回忆册' : parts.join(' · ');
  }

  static String _coverSubtitle(Map<String, dynamic>? user) {
    final birth = _userText(user, 'birth_year');
    final hometown = _userText(user, 'hometown');
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
      return '我们想把这些日子慢慢讲给你听。不是为了写成多么正式的一本书，只是想把家里人还记得的片刻，轻轻放在一起。';
    }
    final caption = _fieldText('caption', coverPhoto.caption);
    if (caption.isNotEmpty) {
      return _ensureSentence(caption);
    }
    final time = _fieldText('photo_time', coverPhoto.photoTime);
    final location = _fieldText('location', coverPhoto.location);
    final people = _fieldText('people_involved', coverPhoto.peopleInvolved);
    final parts = <String>[
      if (time.isNotEmpty && location.isNotEmpty)
        '我们记得，$time，你在$location留下了这一刻。',
      if (time.isNotEmpty && location.isEmpty) '我们记得，$time，这一刻被家里人留了下来。',
      if (time.isEmpty && location.isNotEmpty) '我们记得，你在$location留下了这一刻。',
      if (people.isNotEmpty) '$people也在这个片刻里。',
    ];
    return parts.isEmpty ? '我们想把这些日子慢慢讲给你听。' : parts.join('');
  }

  static String _openingText(
    String elderName,
    List<Map<String, dynamic>> familyMembers,
    List<Map<String, dynamic>> memoryEvents,
    List<ProfilePhotoModel> photos,
  ) {
    final bits = <String>[
      '我们想把这些记忆慢慢讲给你听。',
      if (familyMembers.isNotEmpty) '那些熟悉的名字，也会在故事里轻轻出现。',
      if (memoryEvents.isNotEmpty) '那些被家里人记下的时刻，会一件件连成你走过的路。',
      if (photos.isNotEmpty) '照片里的片刻，也替我们留住了当时的人和地方。',
    ];
    return bits.join('');
  }

  static String _elderProfileContent(
    String elderName,
    Map<String, dynamic>? user,
  ) {
    final hometown = _userText(user, 'hometown');
    final personality = _userText(user, 'personality');
    final hobbies = _userText(user, 'hobbies');
    final career = _userText(user, 'career');
    final parts = <String>[
      if (hometown.isNotEmpty) '我们记得，你从$hometown走来。',
      if (career.isNotEmpty) _careerStory(career),
      if (personality.isNotEmpty) _personalityStory(personality),
      if (hobbies.isNotEmpty) _hobbyStory(hobbies),
    ];
    if (parts.isEmpty) {
      parts.add('关于你的很多记忆，家里人总是从一些小事想起。');
    }
    return parts.join('');
  }

  static String _endingText(String elderName, List<String> missing) {
    return '这些故事还没有讲完。我们会继续陪你，把更多照片、更多声音、更多日子，慢慢放进这本回忆图鉴里。';
  }

  static String _photoTitle(ProfilePhotoModel photo) {
    final caption = _fieldText('caption', photo.caption);
    if (caption.isNotEmpty) return caption;
    final location = _fieldText('location', photo.location);
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
    final caption = _fieldText('caption', photo.caption);
    final time = _fieldText('photo_time', photo.photoTime);
    final location = _fieldText('location', photo.location);
    final people = _fieldText('people_involved', photo.peopleInvolved);
    final elderName = _userText(user, 'name');
    final parts = <String>[];

    if (caption.isNotEmpty) {
      parts.add(_ensureSentence(caption));
    }
    if (time.isNotEmpty || location.isNotEmpty) {
      if (time.isNotEmpty && location.isNotEmpty) {
        parts.add('我们记得，$time，$location留下了这一刻。');
      } else if (time.isNotEmpty) {
        parts.add('$time，这一刻被家人留了下来。');
      } else {
        parts.add('那一刻，$location也被留在了记忆里。');
      }
    }
    if (people.isNotEmpty) {
      parts.add('$people也在这一刻里。');
    }
    if (familyMember != null) {
      final rel = _fieldText('relation', familyMember['relation']);
      final familyName = _fieldText('name', familyMember['name']);
      if (familyName.isNotEmpty) {
        if (rel.isNotEmpty && elderName.isNotEmpty) {
          parts.add('$familyName是你的$rel，这份牵挂也留在这里。');
        } else {
          parts.add('$familyName也和这一刻连在一起。');
        }
      }
    }
    if (memoryEvent != null) {
      final title = _fieldText('title', memoryEvent['title']);
      final desc = _fieldText('description', memoryEvent['description']);
      if (desc.isNotEmpty && !parts.contains(desc)) {
        parts.add(_ensureSentence(desc));
      } else if (title.isNotEmpty) {
        parts.add('我们也会想起“$title”那段日子。');
      }
    }
    return parts.join(' ');
  }

  static List<String> _photoQuestions(ProfilePhotoModel photo) {
    final questions = <String>[];
    if (_fieldText('location', photo.location).isEmpty) {
      questions.add('这张照片是在哪里拍的？');
    }
    if (_fieldText('photo_time', photo.photoTime).isEmpty) {
      questions.add('这张照片大概是哪一年或哪个季节拍的？');
    }
    if (_fieldText('people_involved', photo.peopleInvolved).isEmpty) {
      questions.add('照片里的人分别是谁？');
    }
    if (_fieldText('caption', photo.caption).isEmpty) {
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
        'name': _fieldText('name', row['name']),
        'relation': _fieldText('relation', row['relation']),
        'birthday': _fieldText('birthday', row['birthday']),
        'location': _fieldText('location', row['location']),
        'contact_freq': _fieldText('contact_freq', row['contact_freq']),
        'notes': _fieldText('notes', row['notes']),
        'photo_path': _fieldText('photo_path', row['photo_path']),
        'is_active': _bool01(row['is_active'], defaultValue: true),
      };

  static Map<String, dynamic> _memoryInputRow(Map<String, dynamic> row) => {
        'id': row['id'],
        'event_time': _fieldText('event_time', row['event_time']),
        'title': _fieldText('title', row['title']),
        'description': _fieldText('description', row['description']),
        'location': _fieldText('location', row['location']),
        'people_involved':
            _fieldText('people_involved', row['people_involved']),
        'emotion': _fieldText('emotion', row['emotion']),
        'photo_paths': _decodeStringList(_text(row['photo_paths'])),
        'importance': _int(row['importance']) ?? 3,
        'verified': _bool01(row['verified'], defaultValue: false),
      };

  static Map<String, dynamic> _dailyInputRow(Map<String, dynamic> row) => {
        'date': _fieldText('date', row['date']),
        'breakfast': _fieldText('breakfast', row['breakfast']),
        'lunch': _fieldText('lunch', row['lunch']),
        'dinner': _fieldText('dinner', row['dinner']),
        'activities': _fieldText('activities', row['activities']),
        'people_met': _fieldText('people_met', row['people_met']),
        'places_went': _fieldText('places_went', row['places_went']),
        'mood': _fieldText('mood', row['mood']),
      };

  static Map<String, dynamic> _photoInputRow(ProfilePhotoModel photo) => {
        'photo_id': photo.id,
        'category': _photoCategoryLabel(photo.category),
        'media_type': photo.isVideo ? 'video' : 'image',
        'visible_content': _photoVisibleContent(photo),
        'people': _fieldText('people_involved', photo.peopleInvolved),
        'scene': _fieldText('location', photo.location),
        'emotion': '',
        'objects': <String>[],
        'uncertain_points': [
          if (_fieldText('people_involved', photo.peopleInvolved).isEmpty)
            '缺少人物信息',
          if (_fieldText('caption', photo.caption).isEmpty) '缺少照片说明',
        ],
        'photo_time': _fieldText('photo_time', photo.photoTime),
      };

  static String _photoVisibleContent(ProfilePhotoModel photo) {
    final caption = _fieldText('caption', photo.caption);
    if (caption.isNotEmpty) {
      return photo.isVideo ? '视频：$caption' : caption;
    }
    if (photo.isVideo) return '一段家庭视频';
    return [
      _fieldText('photo_time', photo.photoTime),
      _fieldText('location', photo.location),
      _fieldText('people_involved', photo.peopleInvolved),
    ].where((text) => text.isNotEmpty).join('，');
  }

  static List<String> _importantLabels(Map<String, dynamic>? user) {
    return [
      _userText(user, 'career'),
      _userText(user, 'hobbies'),
      _userText(user, 'personality'),
    ].where((text) => text.isNotEmpty).toList();
  }

  static String _mainCaregiver(List<Map<String, dynamic>> familyMembers) {
    for (final row in familyMembers) {
      final notes = _fieldText('notes', row['notes']);
      if (notes.contains('照护') ||
          notes.contains('照顾') ||
          notes.contains('主要')) {
        return _fieldText('name', row['name']);
      }
    }
    return '';
  }

  static String _familyNotes(List<Map<String, dynamic>> familyMembers) {
    return familyMembers
        .map((row) => _fieldText('notes', row['notes']))
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
        if (_fieldText('location', photo.location).isNotEmpty)
          _fieldText('location', photo.location),
      for (final event in memoryEvents)
        if (_fieldText('location', event['location']).isNotEmpty)
          _fieldText('location', event['location']),
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

  static List<String> _collectQualityWarnings({
    required Map<String, dynamic>? user,
    required List<Map<String, dynamic>> familyMembers,
    required List<Map<String, dynamic>> memoryEvents,
    required List<Map<String, dynamic>> dailyLifeRecords,
    required List<ProfilePhotoModel> photos,
  }) {
    final warnings = <String>[];
    void add(String fieldKey, Object? value, {String? label}) {
      final warning =
          _cleanFieldText(fieldKey, value, labelOverride: label).warning;
      if (warning != null && warning.isNotEmpty) warnings.add(warning);
    }

    for (final key in const [
      'birth_year',
      'hometown',
      'current_address',
      'career',
      'hobbies',
      'food_preference',
      'personality',
      'dialect',
      'care_notes',
      'medical_notes',
    ]) {
      add(key, user?[key]);
    }

    for (final row in familyMembers) {
      final name = _fieldText('name', row['name']);
      final prefix = name.isEmpty ? '亲属信息' : '亲属$name';
      add('relation', row['relation'], label: '$prefix的关系');
      add('location', row['location'], label: '$prefix的所在地');
      add('contact_freq', row['contact_freq'], label: '$prefix的联系频率');
      add('notes', row['notes'], label: '$prefix的备注');
    }

    for (final row in memoryEvents) {
      final title = _fieldText('title', row['title']);
      final prefix = title.isEmpty ? '一段经历' : '经历“$title”';
      add('title', row['title'], label: '$prefix的标题');
      add('description', row['description'], label: '$prefix的描述');
      add('event_time', row['event_time'], label: '$prefix的时间');
      add('location', row['location'], label: '$prefix的地点');
      add('people_involved', row['people_involved'], label: '$prefix的人物');
      add('emotion', row['emotion'], label: '$prefix的感受');
    }

    for (final row in dailyLifeRecords) {
      final date = _fieldText('date', row['date']);
      final prefix = date.isEmpty ? '一条日常记录' : '$date 的日常记录';
      add('breakfast', row['breakfast'], label: '$prefix早饭');
      add('lunch', row['lunch'], label: '$prefix午饭');
      add('dinner', row['dinner'], label: '$prefix晚饭');
      add('activities', row['activities'], label: '$prefix活动');
      add('people_met', row['people_met'], label: '$prefix见到的人');
      add('places_went', row['places_went'], label: '$prefix去过的地方');
      add('mood', row['mood'], label: '$prefix心情');
    }

    for (final photo in photos) {
      final title = _photoTitle(photo);
      final prefix = title.isEmpty ? '一张照片' : '照片“$title”';
      add('caption', photo.caption, label: '$prefix的说明');
      add('photo_time', photo.photoTime, label: '$prefix的时间');
      add('location', photo.location, label: '$prefix的地点');
      add('people_involved', photo.peopleInvolved, label: '$prefix的人物');
    }

    return _dedupeStrings(warnings).take(8).toList();
  }

  static String _userText(Map<String, dynamic>? user, String fieldKey) {
    return _fieldText(fieldKey, user?[fieldKey]);
  }

  static String _fieldText(String fieldKey, Object? value) {
    return _cleanFieldText(fieldKey, value).text;
  }

  static _CleanedAlbumText _cleanFieldText(
    String fieldKey,
    Object? value, {
    String? labelOverride,
  }) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty || _isNoInformationText(raw)) {
      return const _CleanedAlbumText('');
    }

    final label = labelOverride ?? _fieldLabel(fieldKey);
    final extracted = _extractDeclaredValue(fieldKey, raw);
    final candidate = _trimEndingPunctuation(extracted ?? raw).trim();
    if (candidate.isEmpty || _isNoInformationText(candidate)) {
      return const _CleanedAlbumText('');
    }

    final issue = _semanticIssueForField(fieldKey, candidate, raw);
    if (issue != null) {
      return _CleanedAlbumText(
        '',
        warning: '$label“${_shortenForNote(raw)}”$issue，已暂时不写入正文。',
      );
    }
    return _CleanedAlbumText(candidate);
  }

  static String? _extractDeclaredValue(String fieldKey, String raw) {
    final labels = _fieldLabels(fieldKey);
    if (labels.isEmpty) return null;
    final subjects = '(?:老人|长辈|爷爷|奶奶|姥姥|姥爷|外公|外婆|他|她|其)?';
    for (final label in labels) {
      final escaped = RegExp.escape(label);
      final prefix = RegExp('^$subjects(?:的)?$escaped(?:是|为|:|：)?(.+)\$');
      final prefixMatch = prefix.firstMatch(raw);
      if (prefixMatch != null) {
        return prefixMatch.group(1)?.trim();
      }

      final suffix = RegExp('^(.+?)(?:是|属于|作为)$subjects(?:的)?$escaped\$');
      final suffixMatch = suffix.firstMatch(raw);
      if (suffixMatch != null) {
        return suffixMatch.group(1)?.trim();
      }
    }
    return null;
  }

  static String? _semanticIssueForField(
    String fieldKey,
    String candidate,
    String raw,
  ) {
    if (_isBirthYearInvalid(fieldKey, candidate)) {
      return '看起来不太合理';
    }
    if (_looksLikeFieldShell(fieldKey, candidate, raw)) {
      return '像字段说明，不像可以讲进故事的具体内容';
    }
    if (_isTooGenericForField(fieldKey, candidate)) {
      return '太泛了，缺少具体细节';
    }
    return null;
  }

  static bool _isBirthYearInvalid(String fieldKey, String value) {
    if (fieldKey != 'birth_year') return false;
    final normalized = _normalizeForQuality(value);
    final number = int.tryParse(normalized.replaceAll(RegExp(r'[^0-9]'), ''));
    if (number == null) return false;
    final currentYear = DateTime.now().year;
    if (normalized.length <= 3 || normalized.contains('岁')) {
      return number <= 0 || number > 120;
    }
    if (normalized.length >= 4) {
      return number < 1900 || number > currentYear;
    }
    return false;
  }

  static bool _looksLikeFieldShell(
    String fieldKey,
    String candidate,
    String raw,
  ) {
    final normalized = _normalizeForQuality(candidate);
    final rawNormalized = _normalizeForQuality(raw);
    for (final label in _fieldLabels(fieldKey)) {
      final labelNorm = _normalizeForQuality(label);
      if (normalized == labelNorm) return true;
      if (rawNormalized == '老人$labelNorm' ||
          rawNormalized == '老人的$labelNorm' ||
          rawNormalized == '长辈$labelNorm' ||
          rawNormalized == '长辈的$labelNorm') {
        return true;
      }
      if (rawNormalized.endsWith('是$labelNorm') && normalized.length < 6) {
        return true;
      }
    }
    return false;
  }

  static bool _isTooGenericForField(String fieldKey, String value) {
    final normalized = _normalizeForQuality(value);
    final generic = switch (fieldKey) {
      'food_preference' => const {
          '吃饭',
          '吃饭饭',
          '吃东西',
          '饮食',
          '饭',
          '饭菜',
          '食物',
          '一日三餐',
          '三餐',
          '正常吃饭',
          '会吃饭',
          '吃了饭',
          '家常饭',
        },
      'hobbies' => const {
          '爱好',
          '兴趣',
          '兴趣爱好',
          '娱乐',
          '活动',
          '日常活动',
          '生活',
          '休息',
        },
      'career' => const {
          '工作',
          '上班',
          '职业',
          '职业经历',
          '干活',
          '劳动',
        },
      'personality' => const {
          '性格',
          '性格特点',
          '脾气',
          '老人性格',
        },
      'dialect' => const {
          '说话',
          '语言',
          '方言',
          '说话习惯',
        },
      'care_notes' || 'medical_notes' => const {
          '照看',
          '照顾',
          '护理',
          '注意',
          '注意事项',
          '照护提醒',
          '家人照看',
          '老人照看',
          '照看老人',
          '照顾老人',
          '护理老人',
        },
      'breakfast' || 'lunch' || 'dinner' => const {
          '吃饭',
          '吃了饭',
          '吃东西',
          '饭',
          '饭菜',
          '食物',
          '三餐',
          '一日三餐',
          '正常吃饭',
          '早餐',
          '早饭',
          '午餐',
          '午饭',
          '晚餐',
          '晚饭',
        },
      'activities' => const {
          '活动',
          '日常活动',
          '老人活动',
          '做活动',
          '生活',
        },
      'caption' => const {
          '照片',
          '图片',
          '一张照片',
          '这张照片',
          '这个照片',
          '这是照片',
          '这是一张照片',
          '老人照片',
          '视频',
          '一段视频',
          '这段视频',
        },
      'people_involved' => const {
          '人物',
          '照片里的人',
          '图里的人',
          '人',
        },
      'location' || 'places_went' => const {
          '地点',
          '位置',
          '地方',
          '拍摄地点',
          '去过的地方',
        },
      'title' || 'description' => const {
          '往事',
          '经历',
          '事情',
          '故事',
          '回忆',
          '一段往事',
          '一段经历',
        },
      'contact_freq' => const {
          '联系',
          '联系频率',
          '电话',
        },
      'relation' => const {
          '关系',
          '亲属',
          '家属',
        },
      _ => const <String>{},
    };
    return generic.contains(normalized);
  }

  static String _fieldLabel(String fieldKey) {
    final labels = _fieldLabels(fieldKey);
    return labels.isEmpty ? '这条信息' : labels.first;
  }

  static List<String> _fieldLabels(String fieldKey) {
    return switch (fieldKey) {
      'name' => const ['姓名'],
      'gender' => const ['性别'],
      'birth_year' => const ['出生年月/年龄', '出生年', '年龄'],
      'hometown' => const ['籍贯', '老家'],
      'current_address' => const ['现居地', '住址'],
      'career' => const ['职业经历', '职业', '工作'],
      'hobbies' => const ['兴趣爱好', '爱好', '兴趣'],
      'food_preference' => const ['饮食习惯', '饮食偏好', '喜欢吃的', '口味'],
      'personality' => const ['性格特点', '性格'],
      'dialect' => const ['方言/说话习惯', '方言', '说话习惯'],
      'care_notes' => const ['照护提醒', '家人照看', '注意事项'],
      'medical_notes' => const ['健康提醒', '医疗备注', '注意事项'],
      'relation' => const ['关系', '称呼'],
      'birthday' => const ['生日'],
      'location' => const ['地点', '所在地', '位置'],
      'contact_freq' => const ['联系频率'],
      'notes' => const ['备注', '补充说明'],
      'event_time' => const ['时间', '发生时间'],
      'title' => const ['标题'],
      'description' => const ['描述', '故事'],
      'people_involved' => const ['人物', '涉及人物'],
      'emotion' => const ['感受', '心情'],
      'date' => const ['日期'],
      'breakfast' => const ['早饭'],
      'lunch' => const ['午饭'],
      'dinner' => const ['晚饭'],
      'activities' => const ['活动'],
      'people_met' => const ['见到的人'],
      'places_went' => const ['去过的地方'],
      'mood' => const ['心情'],
      'caption' => const ['照片说明', '说明'],
      'photo_time' => const ['照片时间', '时间'],
      'photo_path' => const ['照片路径'],
      _ => const <String>[],
    };
  }

  static List<String> _dedupeStrings(List<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) out.add(trimmed);
    }
    return out;
  }

  static String _normalizeForQuality(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s　。.!！?？,，;；:：、~～_—\-]+'), '');
  }

  static String _shortenForNote(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 24) return trimmed;
    return '${trimmed.substring(0, 24)}…';
  }

  static bool _isGenericKeyword(String normalized) {
    const generic = <String>{
      '吃饭',
      '吃东西',
      '饮食',
      '饭菜',
      '食物',
      '一日三餐',
      '正常吃饭',
      '照看',
      '照顾',
      '照看老人',
      '照顾老人',
      '家人照看',
      '注意事项',
      '活动',
      '日常活动',
      '照片',
      '图片',
      '这是一张照片',
      '人物',
      '地点',
      '故事',
      '回忆',
      '经历',
      '关系',
      '联系',
      '职业',
      '爱好',
      '性格',
    };
    return generic.contains(normalized);
  }

  static Map<String, dynamic> _inputMap(Object? value) {
    if (value is! Map) return const <String, dynamic>{};
    return Map<String, dynamic>.from(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static List<Map<String, dynamic>> _inputMaps(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList();
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
