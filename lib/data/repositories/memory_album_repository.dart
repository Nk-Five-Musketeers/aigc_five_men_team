import 'dart:convert';

import '../../core/narration/narration_text.dart';
import '../../core/prompts/memory_album_prompts.dart';
import '../local_db/local_database.dart';
import '../models/memory_album.dart';
import '../models/profile_photo.dart';
import '../models/profile_video.dart';
import 'chat_repository.dart';

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
  MemoryAlbumRepository({ChatRepository? chatRepository})
      : _chatRepository = chatRepository ?? ChatRepository();

  final ChatRepository _chatRepository;
  static final Map<String, Future<_StoryAlbumResult>> _sessionStoryCache = {};
  static final Map<String, Future<MemoryAlbum>> _sessionAuditCache = {};

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
    final allMedia = MemoryAlbumComposer.dedupePhotosByStoryContent(
      [...imageOnlyPhotos, ..._photosFromVideos(videos)],
    );

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
    final storyResult = await _storyAlbumOncePerRun(
      ownerUserId: ownerUserId,
      album: album,
      generationInput: generationInput,
    );
    final finalAlbum = await _auditAlbumOncePerRun(
      ownerUserId: ownerUserId,
      album: storyResult.album,
      generationInput: generationInput,
      user: user,
    );

    return MemoryAlbumDraft(
      album: finalAlbum,
      photos: allMedia,
      generationInput: generationInput,
    );
  }

  Future<_StoryAlbumResult> _storyAlbumOncePerRun({
    required String ownerUserId,
    required MemoryAlbum album,
    required Map<String, dynamic> generationInput,
  }) async {
    if (!album.hasContent || album.narration.segments.isEmpty) {
      return _StoryAlbumResult(album: album);
    }
    final cacheKey = '$ownerUserId:${_albumInputFingerprint(generationInput)}';
    return _sessionStoryCache.putIfAbsent(
      cacheKey,
      () => _generateStoryAlbumWithAi(
        album: album,
        generationInput: generationInput,
      )
          .timeout(
            const Duration(seconds: 28),
            onTimeout: () => _StoryAlbumResult(
              album: _albumWithStoryFallbackNote(album),
            ),
          )
          .catchError(
            (_) => _StoryAlbumResult(
              album: _albumWithStoryFallbackNote(album),
            ),
          ),
    );
  }

  Future<_StoryAlbumResult> _generateStoryAlbumWithAi({
    required MemoryAlbum album,
    required Map<String, dynamic> generationInput,
  }) async {
    final keywords = MemoryAlbumComposer.storyKeywordsForInput(generationInput);
    if (keywords.isEmpty) {
      return _StoryAlbumResult(album: album);
    }
    final overlay = await _chatRepository.generateMemoryAlbumStoryOverlay(
      generationInput: generationInput,
      localAlbum: album.toJson(),
      keywords: keywords,
    );
    final generated = _applyStoryOverlay(album, overlay);
    return _StoryAlbumResult(album: generated);
  }

  Future<MemoryAlbum> _auditAlbumOncePerRun({
    required String ownerUserId,
    required MemoryAlbum album,
    required Map<String, dynamic> generationInput,
    required Map<String, dynamic>? user,
  }) async {
    if (!album.hasContent || album.narration.segments.isEmpty) return album;
    final cacheKey = '$ownerUserId:${_albumInputFingerprint(generationInput)}';
    return _sessionAuditCache.putIfAbsent(
      cacheKey,
      () => _auditAlbumWithAi(
        album: album,
        generationInput: generationInput,
        user: user,
      )
          .timeout(
            const Duration(seconds: 32),
            onTimeout: () => _albumWithAuditFallbackNote(album),
          )
          .catchError((_) => _albumWithAuditFallbackNote(album)),
    );
  }

  Future<MemoryAlbum> _auditAlbumWithAi({
    required MemoryAlbum album,
    required Map<String, dynamic> generationInput,
    required Map<String, dynamic>? user,
  }) async {
    final blocks = _reviewBlocksForAlbum(album);
    final refs = _sentenceRefsForBlocks(blocks);
    if (refs.isEmpty) return album;

    final selectedRefs = _selectAuditRefs(refs, maxCount: 24);
    final elderProfile =
        Map<String, dynamic>.from(generationInput['elder_profile'] as Map);
    final photoInfos = ((generationInput['photo_analysis_results'] as List?) ??
            const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList();
    final familyNotes = jsonEncode(generationInput['family_notes'] ?? []);
    final boundaryNotes = jsonEncode({
      'taboo': MemoryAlbumComposer._userText(user, 'taboo'),
      'care_notes': MemoryAlbumComposer._userText(user, 'care_notes'),
      'medical_notes': MemoryAlbumComposer._userText(user, 'medical_notes'),
    });

    final decisions = <String, _AuditDecision>{};
    for (final chunk in _chunks(selectedRefs, 12)) {
      final result = await _chatRepository
          .auditMemoryAlbumSentences(
            elderProfile: elderProfile,
            photoInfos: photoInfos,
            familyNotes: familyNotes,
            boundaryNotes: boundaryNotes,
            sentences: chunk.map((ref) => ref.toAuditJson()).toList(),
          )
          .timeout(const Duration(seconds: 18));
      decisions.addAll(_auditDecisionsFromResponse(result));
    }

    if (decisions.isEmpty) {
      return MemoryAlbumComposer.dedupeRepeatedNarrationFacts(album);
    }
    return _applyAuditDecisions(album, blocks, refs, decisions);
  }

  MemoryAlbum _albumWithAuditFallbackNote(MemoryAlbum album) {
    final warnings = MemoryAlbumComposer._dedupeStrings([
      ...album.notes.possibleConflicts,
      '智能润色暂时不可用，已先使用本地规则生成回忆图鉴。',
    ]);
    return album.copyWith(
      notes: album.notes.copyWith(possibleConflicts: warnings),
    );
  }

  MemoryAlbum _albumWithStoryFallbackNote(MemoryAlbum album) {
    final warnings = MemoryAlbumComposer._dedupeStrings([
      ...album.notes.possibleConflicts,
      'AI故事生成暂时不可用，已先使用本地规则生成回忆图鉴。',
    ]);
    return album.copyWith(
      notes: album.notes.copyWith(possibleConflicts: warnings),
    );
  }

  MemoryAlbum _applyStoryOverlay(
    MemoryAlbum album,
    Map<String, dynamic> overlay,
  ) {
    final seenSentences = <String>{};
    final chapterIntroById = _overlayListById(
      overlay['chapter_intros'],
      idKey: 'chapter_id',
    );
    final itemById = _overlayListById(
      overlay['item_contents'],
      idKey: 'item_id',
    );

    String generatedOrFallback(
      Object? raw,
      String fallback, {
      bool allowEmptyFallback = false,
    }) {
      final cleaned = _cleanGeneratedParagraph(
        raw?.toString() ?? '',
        seenSentences: seenSentences,
      );
      if (cleaned.isNotEmpty) return cleaned;
      return allowEmptyFallback ? '' : fallback;
    }

    final chapters = album.chapters.map((chapter) {
      final chapterOverlay = chapterIntroById[chapter.chapterId];
      final items = chapter.items.map((item) {
        final itemOverlay = itemById[item.itemId];
        final rawContent = itemOverlay?['content'];
        final hasLocalStoryFacts = item.content.trim().isNotEmpty;
        final generatedContent = hasLocalStoryFacts
            ? generatedOrFallback(rawContent, item.content)
            : item.content;
        final generatedQuestions =
            _overlayStringList(itemOverlay?['family_questions']);
        return item.copyWith(
          content: generatedContent,
          familyQuestions: MemoryAlbumComposer._dedupeStrings([
            ...item.familyQuestions,
            ...generatedQuestions,
          ]),
        );
      }).toList();
      return chapter.copyWith(
        chapterIntro: generatedOrFallback(
          chapterOverlay?['content'],
          chapter.chapterIntro,
        ),
        items: items,
      );
    }).toList();

    final generatedQuestions = _overlayStringList(overlay['family_questions'])
        .map((question) => FamilyQuestion(
              question: question,
              reason: 'AI根据预录入关键词建议家属补充确认。',
            ))
        .toList();
    final generatedNotes = _overlayStringList(overlay['notes']);

    final reviewed = album.copyWith(
      albumTitle: _cleanGeneratedTitle(
        overlay['album_title'],
        fallback: album.albumTitle,
      ),
      albumSubtitle: _cleanGeneratedTitle(
        overlay['album_subtitle'],
        fallback: album.albumSubtitle,
      ),
      cover: album.cover.copyWith(
        coverText: generatedOrFallback(
          overlay['cover_text'],
          album.cover.coverText,
        ),
      ),
      opening: album.opening.copyWith(
        content: generatedOrFallback(
          overlay['opening_content'],
          album.opening.content,
        ),
      ),
      elderProfileCard: album.elderProfileCard.copyWith(
        content: generatedOrFallback(
          overlay['elder_profile_content'],
          album.elderProfileCard.content,
        ),
      ),
      chapters: chapters,
      ending: album.ending.copyWith(
        content: generatedOrFallback(
          overlay['ending_content'],
          album.ending.content,
        ),
      ),
      familyQuestions: _dedupeFamilyQuestions([
        ...album.familyQuestions,
        ...generatedQuestions,
      ]),
      notes: album.notes.copyWith(
        rewrittenParts: MemoryAlbumComposer._dedupeStrings([
          ...album.notes.rewrittenParts,
          'AI已根据预录入关键词生成故事正文',
        ]),
        possibleConflicts: MemoryAlbumComposer._dedupeStrings([
          ...album.notes.possibleConflicts,
          ...generatedNotes,
        ]),
      ),
      narration: const MemoryAlbumNarration(segments: <NarrationSegment>[]),
    );
    return MemoryAlbumComposer.dedupeRepeatedNarrationFacts(
      reviewed.copyWith(narration: buildAlbumNarration(reviewed)),
    );
  }

  Map<String, Map<String, dynamic>> _overlayListById(
    Object? raw, {
    required String idKey,
  }) {
    if (raw is! List) return const <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      final id = map[idKey]?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      out[id] = map;
    }
    return out;
  }

  List<String> _overlayStringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return MemoryAlbumComposer._dedupeStrings(
      raw
          .map((item) => item.toString().trim())
          .where((item) =>
              item.isNotEmpty &&
              !MemoryAlbumComposer._isNoInformationText(item) &&
              !_generatedSentenceBlocked(item))
          .toList(),
    );
  }

  String _cleanGeneratedTitle(Object? raw, {required String fallback}) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty ||
        MemoryAlbumComposer._isNoInformationText(text) ||
        _generatedSentenceBlocked(text)) {
      return fallback;
    }
    return text.length > 32 ? fallback : text;
  }

  String _cleanGeneratedParagraph(
    String raw, {
    required Set<String> seenSentences,
  }) {
    final sentences = splitNarrationSentences(raw);
    if (sentences.isEmpty) return '';
    final cleaned = <String>[];
    for (final sentence in sentences) {
      final normalized =
          MemoryAlbumComposer._normalizeForQuality(sentence).trim();
      if (normalized.isEmpty || seenSentences.contains(normalized)) continue;
      if (MemoryAlbumComposer._isNoInformationText(sentence)) continue;
      if (_generatedSentenceBlocked(sentence)) continue;
      seenSentences.add(normalized);
      cleaned.add(MemoryAlbumComposer._ensureSentence(sentence));
    }
    return cleaned.join();
  }

  bool _generatedSentenceBlocked(String text) {
    const blockedFragments = [
      '讲到这张照片',
      '看到一张照片',
      '先看看画面',
      '可以把',
      '可以再多说',
      '还可以补',
      '未确认',
      '待补',
      '有一段和',
      '相连的日子',
      '平时的生活里',
      '家人记得',
      '职业为',
      '爱好是',
      '籍贯是',
      '性格是',
      '该老人',
      '此照片展示',
      '该图鉴记录',
      '我们猜想',
      '或许',
      '也许',
      '资料卡',
      '字段',
      '写作',
      '补充提醒',
      'medical_notes',
      'care_notes',
      'taboo',
    ];
    return blockedFragments.any(text.contains);
  }

  static String _albumInputFingerprint(Map<String, dynamic> generationInput) {
    return base64Url.encode(
      utf8.encode(jsonEncode({
        'elder_profile': generationInput['elder_profile'],
        'family_profile': generationInput['family_profile'],
        'life_experience': generationInput['life_experience'],
        'daily_life_info': generationInput['daily_life_info'],
        'photo_analysis_results': generationInput['photo_analysis_results'],
        'family_notes': generationInput['family_notes'],
        'quality': generationInput['input_quality_warnings'],
      })),
    );
  }

  List<_ReviewBlock> _reviewBlocksForAlbum(MemoryAlbum album) {
    return [
      _ReviewBlock(
        blockKey: 'cover',
        itemId: 'cover',
        itemTitle: album.albumTitle,
        chapterTitle: album.albumTitle,
        content: album.cover.coverText,
      ),
      _ReviewBlock(
        blockKey: 'opening',
        itemId: 'opening',
        itemTitle: album.opening.title,
        chapterTitle: album.opening.title,
        content: album.opening.content,
      ),
      _ReviewBlock(
        blockKey: 'elder_profile_card',
        itemId: 'elder_profile_card',
        itemTitle: album.elderProfileCard.title,
        chapterTitle: album.elderProfileCard.title,
        content: album.elderProfileCard.content,
      ),
      for (final chapter in album.chapters) ...[
        _ReviewBlock(
          blockKey: 'chapter_intro:${chapter.chapterId}',
          itemId: '${chapter.chapterId}_intro',
          itemTitle: chapter.chapterTitle,
          chapterTitle: chapter.chapterTitle,
          content: chapter.chapterIntro,
        ),
        for (final item in chapter.items)
          _ReviewBlock(
            blockKey: 'item:${item.itemId}',
            itemId: item.itemId,
            itemTitle: item.title,
            chapterTitle: chapter.chapterTitle,
            content: item.content,
            photoId: item.photoId,
          ),
      ],
      _ReviewBlock(
        blockKey: 'ending',
        itemId: 'ending',
        itemTitle: album.ending.title,
        chapterTitle: album.ending.title,
        content: album.ending.content,
      ),
    ];
  }

  List<_AuditSentenceRef> _sentenceRefsForBlocks(List<_ReviewBlock> blocks) {
    final refs = <_AuditSentenceRef>[];
    for (final block in blocks) {
      final sentences = splitNarrationSentences(block.content);
      for (var i = 0; i < sentences.length; i++) {
        refs.add(
          _AuditSentenceRef(
            sentenceId: '${block.blockKey}:s$i',
            blockKey: block.blockKey,
            itemId: block.itemId,
            chapterTitle: block.chapterTitle,
            text: sentences[i],
            beforeSentence: i > 0 ? sentences[i - 1] : '',
            afterSentence: i < sentences.length - 1 ? sentences[i + 1] : '',
            photoId: block.photoId,
            orderInBlock: i,
          ),
        );
      }
    }
    return refs;
  }

  List<_AuditSentenceRef> _selectAuditRefs(
    List<_AuditSentenceRef> refs, {
    required int maxCount,
  }) {
    final selected = <_AuditSentenceRef>[];
    final seen = <String>{};
    void addAll(Iterable<_AuditSentenceRef> values) {
      for (final ref in values) {
        if (selected.length >= maxCount) return;
        if (seen.add(ref.sentenceId)) selected.add(ref);
      }
    }

    addAll(refs.where((ref) => _needsPriorityAiAudit(ref.text)));
    addAll(refs);
    return selected;
  }

  bool _needsPriorityAiAudit(String text) {
    const patterns = [
      '有一段和',
      '相连的日子',
      '平时的生活里',
      '家人记得',
      '职业为',
      '爱好是',
      '籍贯是',
      '性格是',
      '该老人',
      '此照片展示',
      '该图鉴记录',
      '脾气暴',
      '暴躁',
      '固执',
      '身体不好',
      'care',
      'medical',
    ];
    return patterns.any(text.contains) || text.length > 54;
  }

  List<List<T>> _chunks<T>(List<T> values, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < values.length; i += size) {
      final end = i + size > values.length ? values.length : i + size;
      chunks.add(values.sublist(i, end));
    }
    return chunks;
  }

  Map<String, _AuditDecision> _auditDecisionsFromResponse(
    Map<String, dynamic> response,
  ) {
    final rawResults = response['results'];
    if (rawResults is! List) return const <String, _AuditDecision>{};
    final out = <String, _AuditDecision>{};
    for (final raw in rawResults) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      final sentenceId = item['sentence_id']?.toString().trim() ?? '';
      if (sentenceId.isEmpty) continue;
      final decision = item['decision']?.toString().trim() ?? 'keep';
      out[sentenceId] = _AuditDecision(
        decision: switch (decision) {
          'rewrite' => 'rewrite',
          'remove' => 'remove',
          'ask_family' => 'ask_family',
          _ => 'keep',
        },
        rewriteText: item['rewrite_text']?.toString().trim() ?? '',
        familyQuestion: item['family_question']?.toString().trim() ?? '',
      );
    }
    return out;
  }

  MemoryAlbum _applyAuditDecisions(
    MemoryAlbum album,
    List<_ReviewBlock> blocks,
    List<_AuditSentenceRef> refs,
    Map<String, _AuditDecision> decisions,
  ) {
    final refsByBlock = <String, List<_AuditSentenceRef>>{};
    for (final ref in refs) {
      refsByBlock.putIfAbsent(ref.blockKey, () => []).add(ref);
    }

    final contentByBlock = <String, String>{};
    final questionsByItem = <String, List<String>>{};
    final globalQuestions = <FamilyQuestion>[];
    var changedCount = 0;

    for (final block in blocks) {
      final blockRefs = refsByBlock[block.blockKey] ?? const [];
      if (blockRefs.isEmpty) continue;
      final rebuilt = <String>[];
      for (final ref in blockRefs) {
        final audit = decisions[ref.sentenceId];
        if (audit == null || audit.decision == 'keep') {
          rebuilt.add(ref.text);
          continue;
        }
        changedCount++;
        if (audit.decision == 'rewrite' && audit.rewriteText.isNotEmpty) {
          rebuilt.add(MemoryAlbumComposer._ensureSentence(audit.rewriteText));
          continue;
        }
        if (audit.decision == 'ask_family' && audit.familyQuestion.isNotEmpty) {
          if (ref.itemId.startsWith('photo_') ||
              ref.itemId.startsWith('life_') ||
              ref.itemId.startsWith('family_')) {
            questionsByItem
                .putIfAbsent(ref.itemId, () => [])
                .add(audit.familyQuestion);
          } else {
            globalQuestions.add(FamilyQuestion(
              question: audit.familyQuestion,
              reason: 'AI 审核认为这里需要家属补充确认。',
            ));
          }
        }
      }
      contentByBlock[block.blockKey] = rebuilt.join();
    }

    if (changedCount == 0) {
      return MemoryAlbumComposer.dedupeRepeatedNarrationFacts(
        album.copyWith(
          notes: album.notes.copyWith(
            rewrittenParts: MemoryAlbumComposer._dedupeStrings([
              ...album.notes.rewrittenParts,
              'AI句子审核已完成',
            ]),
          ),
        ),
      );
    }

    final chapters = album.chapters.map((chapter) {
      final introKey = 'chapter_intro:${chapter.chapterId}';
      final items = chapter.items.map((item) {
        final itemKey = 'item:${item.itemId}';
        final extraQuestions = questionsByItem[item.itemId] ?? const [];
        return item.copyWith(
          content: contentByBlock[itemKey],
          familyQuestions: MemoryAlbumComposer._dedupeStrings([
            ...item.familyQuestions,
            ...extraQuestions,
          ]),
        );
      }).toList();
      return chapter.copyWith(
        chapterIntro: contentByBlock[introKey],
        items: items,
      );
    }).toList();

    final reviewed = album.copyWith(
      cover: album.cover.copyWith(coverText: contentByBlock['cover']),
      opening: album.opening.copyWith(content: contentByBlock['opening']),
      elderProfileCard: album.elderProfileCard.copyWith(
        content: contentByBlock['elder_profile_card'],
      ),
      chapters: chapters,
      ending: album.ending.copyWith(content: contentByBlock['ending']),
      familyQuestions: _dedupeFamilyQuestions([
        ...album.familyQuestions,
        ...globalQuestions,
      ]),
      notes: album.notes.copyWith(
        rewrittenParts: MemoryAlbumComposer._dedupeStrings([
          ...album.notes.rewrittenParts,
          'AI句子审核已处理 $changedCount 句',
        ]),
      ),
      narration: const MemoryAlbumNarration(segments: <NarrationSegment>[]),
    );
    return MemoryAlbumComposer.dedupeRepeatedNarrationFacts(
      reviewed.copyWith(narration: buildAlbumNarration(reviewed)),
    );
  }

  List<FamilyQuestion> _dedupeFamilyQuestions(List<FamilyQuestion> questions) {
    final seen = <String>{};
    final out = <FamilyQuestion>[];
    for (final question in questions) {
      if (seen.add(question.question)) out.add(question);
    }
    return out;
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

class _StoryAlbumResult {
  const _StoryAlbumResult({
    required this.album,
  });

  final MemoryAlbum album;
}

class _ReviewBlock {
  const _ReviewBlock({
    required this.blockKey,
    required this.itemId,
    required this.itemTitle,
    required this.chapterTitle,
    required this.content,
    this.photoId = '',
  });

  final String blockKey;
  final String itemId;
  final String itemTitle;
  final String chapterTitle;
  final String content;
  final String photoId;
}

class _AuditSentenceRef {
  const _AuditSentenceRef({
    required this.sentenceId,
    required this.blockKey,
    required this.itemId,
    required this.chapterTitle,
    required this.text,
    required this.beforeSentence,
    required this.afterSentence,
    required this.photoId,
    required this.orderInBlock,
  });

  final String sentenceId;
  final String blockKey;
  final String itemId;
  final String chapterTitle;
  final String text;
  final String beforeSentence;
  final String afterSentence;
  final String photoId;
  final int orderInBlock;

  Map<String, dynamic> toAuditJson() {
    return {
      'sentence_id': sentenceId,
      'text': text,
      'chapter_title': chapterTitle,
      'before_sentence': beforeSentence,
      'after_sentence': afterSentence,
      'related_block_id': itemId,
      'related_photo_id': photoId,
      'order': orderInBlock,
    };
  }
}

class _AuditDecision {
  const _AuditDecision({
    required this.decision,
    required this.rewriteText,
    required this.familyQuestion,
  });

  final String decision;
  final String rewriteText;
  final String familyQuestion;
}

class _DuplicateFactReport {
  var removedSentences = 0;
  var removedItems = 0;

  int get totalRemoved => removedSentences + removedItems;
  bool get changed => totalRemoved > 0;
}

class _CleanedAlbumText {
  const _CleanedAlbumText(this.text, {this.warning});

  final String text;
  final String? warning;
}
