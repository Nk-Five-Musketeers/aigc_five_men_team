import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../data/models/chat_message.dart';
import '../data/models/extracted_relation_hint.dart';
import '../data/models/memory_extraction_payload.dart';
import '../data/models/relation_conflict_record.dart';
import '../data/local_db/local_database.dart';
import '../data/repositories/chat_repository.dart';
import '../core/voice_input/voice_input.dart';
import 'profile_photo_reply.dart';
import 'relation_extractor.dart';
import 'prompt_task_router.dart';
import '../data/models/profile_photo.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({ChatRepository? repository})
      : _repository = repository ?? ChatRepository() {
    _initFuture = _initializeLocalHistory();
  }

  static const String defaultUserId = 'local_user_default';
  static const String defaultConversationId = 'local_conversation_home';

  final ChatRepository _repository;
  final List<ChatMessage> _messages = <ChatMessage>[];
  late final Future<void> _initFuture;

  /// 当前本地使用者（老人账号）；周围人与会话均按此划分。
  String _activeUserId = defaultUserId;
  late String _activeConversationId;

  List<RelationConflictRecord> _pendingConflicts = <RelationConflictRecord>[];

  bool _isSending = false;
  int _userTurnCount = 0;
  String _lastUserText = '';

  bool get isSending => _isSending;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  String get activeUserId => _activeUserId;

  String get activeConversationId => _activeConversationId;

  List<RelationConflictRecord> get pendingRelationConflicts =>
      List.unmodifiable(_pendingConflicts);

  /// 语音转写后整理：优先大模型润色，失败再本地 NLP，仍失败则返回 [raw]。
  Future<String> polishSpeechBeforeSend(String raw) async {
    await _initFuture;
    final t = raw.trim();
    if (t.isEmpty) return raw;

    final namesHint = await _knownNamesHintForSpeechPolish();

    try {
      final polished = await _repository
          .polishSpeechTranscript(t, knownNamesHint: namesHint)
          .timeout(const Duration(seconds: 45));
      final out = polished.trim();
      if (out.isNotEmpty) return out;
    } catch (e, st) {
      debugPrint('[speech_polish] 大模型润色失败，尝试本地: $e\n$st');
    }
    try {
      final polished = await _repository
          .polishSpeechTranscriptLocal(t)
          .timeout(const Duration(seconds: 8));
      final out = polished.trim();
      if (out.isNotEmpty) return out;
    } catch (e, st) {
      debugPrint('[speech_polish] 本地 NLP 不可用: $e\n$st');
    }
    return t;
  }

  /// 供语音润色对照的档案人名/称谓（不写入对话抽取逻辑）。
  Future<String> _knownNamesHintForSpeechPolish() async {
    try {
      final lines = <String>[];
      final familyRows =
          await LocalDatabase.listFamilyMembersForUser(_activeUserId);
      for (final r in familyRows.take(12)) {
        final name = (r['name'] as String?)?.trim() ?? '';
        if (name.length < 2) continue;
        final rel = (r['relation'] as String?)?.trim() ?? '';
        lines.add(rel.isEmpty ? name : '$rel $name');
      }
      final nearbyRows =
          await LocalDatabase.getNearbyPeopleForUser(_activeUserId);
      for (final r in nearbyRows.take(12)) {
        final name = (r['name'] as String?)?.trim() ?? '';
        if (name.length < 2) continue;
        final rel = (r['relation'] as String?)?.trim() ?? '';
        lines.add(rel.isEmpty ? name : '$rel $name');
      }
      if (lines.isEmpty) return '';
      return lines.join('；');
    } catch (_) {
      return '';
    }
  }

  Future<void> sendMessage(
    String content, {
    Duration networkTimeout = const Duration(seconds: 110),
  }) async {
    await _initFuture;
    final text = content.trim();
    if (text.isEmpty || _isSending) return;

    _userTurnCount += 1;
    _lastUserText = text;
    final userMessage = _textMessage(content: text, isUser: true);
    _messages.add(userMessage);
    await _trySaveMessage(userMessage);
    _isSending = true;
    notifyListeners();

    final photoReply = await ProfilePhotoReplyResolver.resolve(
      ownerUserId: _activeUserId,
      userText: text,
    );

    if (photoReply.status == ProfilePhotoReplyStatus.needsClarification) {
      try {
        final clarify = _textMessage(
          content: photoReply.clarifyMessage!,
          isUser: false,
        );
        _messages.add(clarify);
        await _trySaveMessage(clarify);
        await _extractRelationsFromRecentChat(sourceMessageId: userMessage.id);
      } finally {
        _isSending = false;
        notifyListeners();
      }
      return;
    }

    try {
      final reply = await _repository
          .sendMessage(
            history: _messages,
            promptContext: await _buildPromptContextAsync(),
          )
          .timeout(networkTimeout);
      final assistantMessage = _textMessage(content: reply, isUser: false);
      _messages.add(assistantMessage);
      await _trySaveMessage(assistantMessage);
      await _attachProfilePhotoReplies(photoReply);
      await _extractRelationsFromRecentChat(sourceMessageId: userMessage.id);
      await _insertSupportCardIfNeeded(text);
    } catch (error) {
      final errorMessage = ChatMessage(
        id: _newId('error'),
        content: _buildErrorMessage(error),
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.error,
      );
      _messages.add(errorMessage);
      await _trySaveMessage(errorMessage);
      await _extractRelationsFromRecentChat(sourceMessageId: userMessage.id);
      await _insertLocalMemoryPrompt(text);
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void sendOption(String text) {
    sendMessage(text);
  }

  /// 删除一条本地聊天记录（数据库 + 当前内存列表）。
  Future<void> deleteMessageById(String messageId) async {
    await _initFuture;
    await LocalDatabase.deleteMessageById(messageId);
    _messages.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  /// 清空默认会话的全部聊天历史，并插入一条新的欢迎语。
  Future<void> clearHomeConversationHistory() async {
    await _initFuture;
    await LocalDatabase.deleteAllMessagesInConversation(_activeConversationId);
    _messages.clear();
    _userTurnCount = 0;
    final welcome = ChatMessage(
      id: _newId('welcome'),
      content: '今天想聊什么？我在这里陪着您，慢慢说就好。',
      isUser: false,
      timestamp: DateTime.now(),
    );
    _messages.add(welcome);
    await _trySaveMessage(welcome);
    notifyListeners();
  }

  /// 新建一位本地使用者并切换到该账号。
  Future<void> createLocalProfile(String displayName) async {
    await _initFuture;
    final name = displayName.trim();
    if (name.isEmpty) return;
    final id = 'user_${DateTime.now().microsecondsSinceEpoch}';
    await LocalDatabase.insertUser({
      'id': id,
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
    await LocalDatabase.ensureHomeConversationForUser(id);
    await setActiveUserId(id);
  }

  Future<void> setActiveUserId(String userId) async {
    await _initFuture;
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    _activeConversationId =
        await LocalDatabase.ensureHomeConversationForUser(userId);
    await _loadMessagesFromDb();
    await _reloadPendingConflicts();
    notifyListeners();
  }

  Future<void> resolveRelationConflictUi(String conflictId, bool useNew) async {
    await _initFuture;
    await LocalDatabase.resolveRelationConflict(
      conflictId: conflictId,
      useNew: useNew,
    );
    await _reloadPendingConflicts();
    notifyListeners();
  }

  ChatMessage _textMessage({
    required String content,
    required bool isUser,
  }) {
    return ChatMessage(
      id: _newId(isUser ? 'user' : 'assistant'),
      content: content,
      isUser: isUser,
      timestamp: DateTime.now(),
    );
  }

  ChatMessage _photoMessage(ProfilePhotoModel photo) {
    final label = ProfilePhotoReplyResolver.describePhoto(photo);
    return ChatMessage(
      id: _newId('photo'),
      content: photo.caption?.trim().isNotEmpty == true
          ? photo.caption!.trim()
          : '给您看这张$label',
      isUser: false,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.photo,
      imagePath: photo.filePath,
      profilePhotoId: photo.id,
    );
  }

  Future<void> _attachProfilePhotoReplies(ProfilePhotoReplyResult photoReply) async {
    switch (photoReply.status) {
      case ProfilePhotoReplyStatus.notRequested:
        return;
      case ProfilePhotoReplyStatus.noPhotosInDb:
        final hint = _textMessage(
          content: '档案里还没有保存照片，您可以先在「数据预录入」里添加几张。',
          isUser: false,
        );
        _messages.add(hint);
        await _trySaveMessage(hint);
        return;
      case ProfilePhotoReplyStatus.noMatch:
        final hint = _textMessage(
          content: '我没在照片档案里找到特别对得上的。您可以说要看哪一类，比如「家庭照片」或家里人名字。',
          isUser: false,
        );
        _messages.add(hint);
        await _trySaveMessage(hint);
        return;
      case ProfilePhotoReplyStatus.needsClarification:
        return;
      case ProfilePhotoReplyStatus.matched:
        for (final photo in photoReply.photos) {
          final msg = _photoMessage(photo);
          _messages.add(msg);
          await _trySaveMessage(msg);
        }
        return;
    }
  }

  Future<void> _insertSupportCardIfNeeded(String latestUserText) async {
    if (_userTurnCount % 3 == 0) {
      final card = ChatMessage(
        id: _newId('cognitive'),
        title: '小小回忆练习',
        content: '我这里有一张老家院子的照片。您还记得院子里常放着什么吗？',
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.cognitivePrompt,
        cueLabel: '老家小院',
        options: const <String>['水缸', '自行车', '再想想'],
      );
      _messages.add(card);
      await _trySaveMessage(card);
      return;
    }

    if (_mentionsMemory(latestUserText) || _userTurnCount % 2 == 0) {
      final card = ChatMessage(
        id: _newId('memory'),
        title: '记忆锚点',
        content: '记得您说过以前常骑自行车去上班。那时候早晨路上会不会有点冷？',
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.memoryPrompt,
        cueLabel: '1986 · 自行车',
        options: const <String>['有点冷', '不太冷', '记不清了'],
      );
      _messages.add(card);
      await _trySaveMessage(card);
    }
  }

  Future<void> _insertLocalMemoryPrompt(String latestUserText) async {
    if (!_mentionsMemory(latestUserText)) return;
    final memoryPrompt = ChatMessage(
      id: _newId('local-memory'),
      title: '我们慢慢回忆',
      content: '您刚刚提到了以前的事。要不要从“老家小院的午后”开始说起？',
      isUser: false,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.memoryPrompt,
      cueLabel: '老家小院',
      options: const <String>['好呀', '想看照片', '再等等'],
    );
    _messages.add(memoryPrompt);
    await _trySaveMessage(memoryPrompt);
  }

  bool _mentionsMemory(String text) {
    return text.contains('以前') ||
        text.contains('照片') ||
        text.contains('女儿') ||
        text.contains('上班') ||
        text.contains('老家') ||
        text.contains('自行车') ||
        text.contains('记得');
  }

  /// 老人画像 + 本地库已存档案（预录入/抽取），供重启后对话引用。
  Future<String> _buildElderBriefWithStoredData(
    Map<String, dynamic>? user,
  ) async {
    var brief = _buildElderBrief(user);
    final storedLines =
        await LocalDatabase.queryMemoryContextLinesForUser(_activeUserId);
    final storedBody = storedLines
        .where((l) => !l.contains('暂无'))
        .map((l) => l.startsWith('- ') ? l.substring(2) : l)
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
    if (storedBody.isEmpty) return brief;
    if (brief == '（暂无详细档案）') return storedBody;
    return '$brief\n$storedBody';
  }

  /// 与 `server/prompts` v1.1 对齐；通过 PromptTaskRouter 决定 active_task。
  Future<Map<String, dynamic>> _buildPromptContextAsync() async {
    try {
      final user = await LocalDatabase.getUserById(_activeUserId);
      final route = await PromptTaskRouter.resolve(
        userText: _lastUserText,
        ownerUserId: _activeUserId,
        recentHistory: _messages,
      );
      return <String, dynamic>{
        'global': <String, dynamic>{
          'dialect': (user?['dialect'] as String?)?.trim().isNotEmpty == true
              ? user!['dialect']
              : '天津话',
          'sensitive_topics': _splitTaboo(user?['taboo'] as String?),
          'elder_profile_brief': await _buildElderBriefWithStoredData(user),
        },
        'memory_snippets': route.memorySnippets,
        if (route.activeTask != null) 'active_task': route.activeTask,
        if (route.activeTask != null) 'task': route.taskParams,
      };
    } catch (_) {
      // 降级：仅 global，无任务模块
      return <String, dynamic>{
        'global': <String, dynamic>{
          'dialect': '天津话',
          'sensitive_topics': <String>[],
          'elder_profile_brief': '（暂无详细档案）',
        },
        'memory_snippets': <String>[],
      };
    }
  }

  /// 从 users.taboo 字段拆分敏感话题列表。
  static List<String> _splitTaboo(String? taboo) {
    if (taboo == null || taboo.trim().isEmpty) return <String>[];
    return taboo
        .split(RegExp(r'[,，;；、\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 从 users 档案拼成一行简短老人画像（≤ 80 字）。
  static String _buildElderBrief(Map<String, dynamic>? user) {
    if (user == null) return '（暂无详细档案）';
    final parts = <String>[];
    void add(String label, String key) {
      final v = (user[key] as String?)?.trim();
      if (v != null && v.isNotEmpty) {
        parts.add('$label$v');
      }
    }

    add('', 'name');
    add('', 'birth_year');
    add('籍贯', 'hometown');
    add('职业', 'career');
    add('爱好', 'hobbies');
    add('性格', 'personality');
    if (parts.isEmpty) return '（暂无详细档案）';
    return parts.join('，');
  }

  String _buildErrorMessage(Object error) {
    if (error is TimeoutException) {
      return '我这会儿思考有点慢，先把这句记下了。您可以继续说下一句。';
    }
    if (error is DioException) {
      final detail = _dioUserHint(error);
      return '我这会儿有点连不上大模型服务，但我还在。$detail';
    }
    return '我刚刚没有听清楚，您可以再慢慢说一遍。';
  }

  String _dioUserHint(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return '请在电脑上先启动本地代理：在含 env 与 aigc_five_men_team 的仓库根目录执行 `conda activate ./env` 后运行 `python aigc_five_men_team\\server\\local_chat_server.py`（需配置 VIVO_APP_KEY），并确认地址为 ${AppConstants.apiBaseUrl}。';
    }
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return '（详情：${data['error']}）';
    }
    if (e.message != null && e.message!.isNotEmpty) {
      return '（${e.message}）';
    }
    return '';
  }

  String _newId(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _initializeLocalHistory() async {
    try {
      await LocalDatabase.insertUser({
        'id': defaultUserId,
        'name': '王阿姨',
        'created_at': DateTime.now().toIso8601String(),
      });
      _activeConversationId =
          await LocalDatabase.ensureHomeConversationForUser(_activeUserId);
      await LocalDatabase.addConversationMember(
        _activeConversationId,
        _activeUserId,
        role: 'owner',
      );
      await _loadMessagesFromDb();
      await _reloadPendingConflicts();
    } catch (e, st) {
      debugPrint('ChatProvider: 本地数据库初始化失败: $e');
      debugPrint('$st');
      if (_messages.isEmpty) {
        _messages.add(
          ChatMessage(
            id: 'welcome_fallback',
            content: '今天想聊什么？我在这里陪着您，慢慢说就好。',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      }
    }
    unawaited(VoiceInputService.prepareEngine());
    notifyListeners();
  }

  Future<void> _loadMessagesFromDb() async {
    final rows = await LocalDatabase.getMessagesForConversation(
      _activeConversationId,
    );
    _messages
      ..clear()
      ..addAll(rows.map(_chatMessageFromRow));
    _userTurnCount = _messages.where((m) => m.isUser).length;

    if (_messages.isEmpty) {
      final welcome = ChatMessage(
        id: _newId('welcome'),
        content: '今天想聊什么？我在这里陪着您，慢慢说就好。',
        isUser: false,
        timestamp: DateTime.now(),
      );
      _messages.add(welcome);
      await _trySaveMessage(welcome);
    }
  }

  Future<void> _reloadPendingConflicts() async {
    try {
      final rows =
          await LocalDatabase.getPendingRelationConflicts(_activeUserId);
      _pendingConflicts =
          rows.map(RelationConflictRecord.fromRow).toList(growable: false);
    } catch (_) {
      _pendingConflicts = [];
    }
  }

  /// 在助手回复写入后调用：用大模型从近期对话 JSON 抽取人物，失败则回退本地规则。
  Future<void> _extractRelationsFromRecentChat(
      {required String sourceMessageId}) async {
    await LocalDatabase.ensureUserExists(_activeUserId);

    var llmHintCount = 0;
    var ruleHintCount = 0;
    var processed = 0;

    try {
      final transcript = _buildExtractionTranscript();
      if (transcript.isEmpty) {
        await LocalDatabase.recordRelationExtractionSummary(
          userId: _activeUserId,
          llmHintCount: 0,
          ruleHintCount: 0,
          hintsProcessed: 0,
        );
        return;
      }

      final nearbySummary = await _nearbySummaryForLlm();
      var payload = MemoryExtractionPayload.empty();

      try {
        payload = await _repository
            .extractFullMemoryFromChat(
              transcriptMessages: transcript,
              existingNearbySummary: nearbySummary,
              existingUserSummary: await _userProfileSummaryForLlm(),
            )
            .timeout(const Duration(seconds: 55));
        llmHintCount = payload.people.length;
      } catch (e, st) {
        debugPrint('[relation_extract] LLM 调用失败: $e\n$st');
      }

      var hints = payload.people;
      if (hints.isEmpty) {
        final fullText = transcript.map((e) => e['content'] ?? '').join('\n');
        hints = RelationExtractor.extract(fullText);
        ruleHintCount = hints.length;
      }

      try {
        await _applyElderProfilePatch(payload.elderProfilePatch);
      } catch (e, st) {
        debugPrint('[relation_extract] 更新老人本人档案失败: $e\n$st');
      }
      try {
        await _applyExtractedFamilyMembers(payload.familyMemberRows);
      } catch (e, st) {
        debugPrint('[relation_extract] 家庭成员写入失败: $e\n$st');
      }
      try {
        await _applyExtractedMemoryEvents(payload.memoryEventRows);
      } catch (e, st) {
        debugPrint('[relation_extract] 记忆事件写入失败: $e\n$st');
      }
      try {
        await _applyDailyLifePatch(
          payload.dailyLifePatch,
          sourceMessageId: sourceMessageId,
          rawJson: payload.rawAssistantJson,
        );
      } catch (e, st) {
        debugPrint('[relation_extract] 每日生活记录写入失败: $e\n$st');
      }

      for (final h in hints) {
        try {
          await _applyExtractedHint(h, sourceMessageId);
          processed++;
        } catch (e, st) {
          debugPrint('[relation_extract] 写入周围人失败 (${h.name}): $e\n$st');
        }
      }

      await LocalDatabase.recordRelationExtractionSummary(
        userId: _activeUserId,
        llmHintCount: llmHintCount,
        ruleHintCount: ruleHintCount,
        hintsProcessed: processed,
      );

      await _reloadPendingConflicts();
      notifyListeners();
    } catch (e, st) {
      debugPrint('[relation_extract] 抽取流程异常: $e\n$st');
      await LocalDatabase.recordRelationExtractionSummary(
        userId: _activeUserId,
        llmHintCount: llmHintCount,
        ruleHintCount: ruleHintCount,
        hintsProcessed: processed,
      );
    }
  }

  /// 仅收录**用户（老人）**的文本发言，不包含助手回复，供抽取模型使用，避免把模型幻觉写进档案。
  List<Map<String, String>> _buildExtractionTranscript() {
    final userLines = _messages
        .where(
          (m) => m.isUser && m.kind == ChatMessageKind.text,
        )
        .toList();
    const maxUserTurns = 28;
    final recent = userLines.length > maxUserTurns
        ? userLines.sublist(userLines.length - maxUserTurns)
        : userLines;
    return recent
        .map(
          (m) => <String, String>{
            'role': 'user',
            'content': m.content,
          },
        )
        .toList();
  }

  Future<String> _userProfileSummaryForLlm() async {
    try {
      final u = await LocalDatabase.getUserById(_activeUserId);
      if (u == null) return '（尚无老人档案）';
      final parts = <String>[];
      void add(String label, String key) {
        final v = (u[key] as String?)?.trim();
        if (v != null && v.isNotEmpty) {
          parts.add('$label:$v');
        }
      }

      add('称呼', 'name');
      add('性别', 'gender');
      add('出生年月', 'birth_year');
      add('籍贯', 'hometown');
      add('现居地', 'current_address');
      add('职业经历', 'career');
      add('兴趣爱好', 'hobbies');
      add('饮食习惯', 'food_preference');
      add('性格', 'personality');
      add('忌讳', 'taboo');
      add('方言', 'dialect');
      add('照护提醒', 'care_notes');
      add('健康注意事项', 'medical_notes');
      return parts.isEmpty ? '（尚无老人档案）' : parts.join('；');
    } catch (_) {
      return '（读取老人档案失败）';
    }
  }

  Future<void> _applyElderProfilePatch(Map<String, String> patch) async {
    if (patch.isEmpty) return;
    await LocalDatabase.ensureUserExists(_activeUserId);
    await LocalDatabase.updateUser(_activeUserId, patch);
  }

  Future<void> _applyExtractedFamilyMembers(
    List<Map<String, dynamic>> rows,
  ) async {
    for (final raw in rows) {
      final r = Map<String, dynamic>.from(raw);
      final name = (r['name'] as String?)?.trim() ?? '';
      if (name.length < 2) continue;
      final relation = (r['relation'] as String?)?.trim() ?? '';
      final existing = await LocalDatabase.findFamilyMemberByOwnerNameRelation(
        _activeUserId,
        name,
        relation,
      );
      if (existing != null) {
        final id = (existing['id'] as num).toInt();
        final patch = <String, dynamic>{};
        r.forEach((key, value) {
          if (key == 'name') return;
          if (value == null) return;
          if (value is String && value.trim().isEmpty) return;
          patch[key] = value;
        });
        if (patch.isNotEmpty) {
          await LocalDatabase.updateFamilyMember(id, patch);
        }
      } else {
        await LocalDatabase.insertFamilyMember({
          'owner_user_id': _activeUserId,
          ...r,
        });
      }
    }
  }

  Future<void> _applyExtractedMemoryEvents(
    List<Map<String, dynamic>> rows,
  ) async {
    for (final raw in rows) {
      final r = Map<String, dynamic>.from(raw);
      final title = (r['title'] as String?)?.trim() ?? '';
      if (title.length < 2) continue;
      final eventTime = (r['event_time'] as String?)?.trim() ?? '';
      final eid = await LocalDatabase.findMemoryEventIdByOwnerTitleEventTime(
        _activeUserId,
        title,
        eventTime,
      );
      if (eid != null) {
        final patch = <String, dynamic>{};
        r.forEach((key, value) {
          if (key == 'title' || key == 'event_time') return;
          if (value == null) return;
          if (value is String && value.trim().isEmpty) return;
          patch[key] = value;
        });
        if (patch.isNotEmpty) {
          await LocalDatabase.updateMemoryEvent(eid, patch);
        }
      } else {
        await LocalDatabase.insertMemoryEvent({
          'owner_user_id': _activeUserId,
          ...r,
        });
      }
    }
  }

  String _extractedFieldStr(dynamic v) => v?.toString().trim() ?? '';

  Future<void> _applyDailyLifePatch(
    Map<String, dynamic>? patch, {
    required String sourceMessageId,
    String? rawJson,
  }) async {
    if (patch == null || patch.isEmpty) return;
    var dateStr = _extractedFieldStr(patch['date']);
    if (dateStr.isEmpty) {
      dateStr = DateTime.now().toIso8601String().split('T').first;
    }
    final breakfast = _extractedFieldStr(patch['breakfast']);
    final lunch = _extractedFieldStr(patch['lunch']);
    final dinner = _extractedFieldStr(patch['dinner']);
    final activities = _extractedFieldStr(patch['activities']);
    final peopleMet = _extractedFieldStr(patch['people_met']);
    final placesWent = _extractedFieldStr(patch['places_went']);
    final mood = _extractedFieldStr(patch['mood']);
    final hasContent = breakfast.isNotEmpty ||
        lunch.isNotEmpty ||
        dinner.isNotEmpty ||
        activities.isNotEmpty ||
        peopleMet.isNotEmpty ||
        placesWent.isNotEmpty ||
        mood.isNotEmpty;
    if (!hasContent) return;

    await LocalDatabase.upsertDailyLifeRecordByDate({
      'owner_user_id': _activeUserId,
      'date': dateStr,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'activities': activities,
      'people_met': peopleMet,
      'places_went': placesWent,
      'mood': mood,
      'source_dialog': sourceMessageId,
      'raw_extract': rawJson ?? json.encode(patch),
    });
  }

  Future<String> _nearbySummaryForLlm() async {
    try {
      final rows = await LocalDatabase.getNearbyPeopleForUser(_activeUserId);
      if (rows.isEmpty) return '（尚无已保存条目）';
      final lines = <String>[];
      for (final r in rows) {
        final name = (r['name'] as String?)?.trim() ?? '';
        final rel = (r['relation'] as String?)?.trim() ?? '';
        final phone = (r['phone'] as String?)?.trim() ?? '';
        final note = (r['note'] as String?)?.trim() ?? '';
        lines.add(
          '- $name | 关系:${rel.isEmpty ? '（空）' : rel} | 电话:${phone.isEmpty ? '（空）' : phone}'
          '${note.isEmpty ? '' : ' | 备注:$note'}',
        );
      }
      return lines.join('\n');
    } catch (_) {
      return '（读取周围人档案失败）';
    }
  }

  bool _meaningfullyDifferent(String? a, String? b) {
    final x = (a ?? '').trim();
    final y = (b ?? '').trim();
    if (x.isEmpty || y.isEmpty) return false;
    return x != y;
  }

  /// 比较规范化后的姓名，避免仅空格差异触发「姓名冲突」。
  bool _meaningfullyDifferentPersonName(String? a, String? b) {
    final x = LocalDatabase.normalizePersonName(a);
    final y = LocalDatabase.normalizePersonName(b);
    if (x.length < 2 || y.length < 2) return false;
    return x != y;
  }

  /// 先按姓名匹配；否则在称谓槽位上仅对应一条档案时，按称谓视为同一人（用于姓名更正，避免重复建条）。
  Future<Map<String, dynamic>?> _resolveExistingNearbyRow(
    ExtractedRelationHint h,
  ) async {
    final norm = LocalDatabase.normalizePersonName(h.name);
    if (norm.length < 2) return null;

    final byName = await LocalDatabase.findNearbyPersonByNormalizedName(
      _activeUserId,
      norm,
    );
    if (byName != null) return byName;

    // 同一称谓下可有多人：仅当抽取端显式给出 same_relation_key（用户强调「某人不对/记错」等）
    // 时才按称谓槽位对齐已有行，否则一律新建档案，避免误把新人合并进旧人并弹出冲突。
    final srk = LocalDatabase.normalizeRelationLabel(h.sameRelationKey);
    if (srk.isEmpty) return null;

    final candidates = await LocalDatabase.findNearbyPeopleByNormalizedRelation(
      _activeUserId,
      srk,
    );
    if (candidates.length != 1) return null;
    return candidates.first;
  }

  Future<void> _applyExtractedHint(
      ExtractedRelationHint h, String sourceMessageId) async {
    final norm = LocalDatabase.normalizePersonName(h.name);
    if (norm.length < 2) return;

    final existing = await _resolveExistingNearbyRow(h);

    if (existing == null) {
      await LocalDatabase.upsertNearbyPerson({
        'id': 'nearby_${DateTime.now().microsecondsSinceEpoch}',
        'owner_user_id': _activeUserId,
        'name': h.name.trim(),
        'relation': h.relation,
        'phone': h.phone,
        'note': h.note,
      });
      return;
    }

    final id = existing['id'] as String;
    final oldName = existing['name'] as String?;
    final oldRel = existing['relation'] as String?;
    final oldPhone = existing['phone'] as String?;
    final oldNote = existing['note'] as String?;

    // 同一档案同一时间只保留一条待确认冲突（insert 内会先删该档案旧 pending）。
    // 单次抽取内优先提示：姓名 > 称谓 > 电话 > 备注。
    String? conflictField;
    String? conflictOld;
    String? conflictNew;
    if (_meaningfullyDifferentPersonName(oldName, h.name)) {
      conflictField = 'name';
      conflictOld = oldName;
      conflictNew = h.name.trim();
    } else if (h.relation != null &&
        _meaningfullyDifferent(oldRel, h.relation)) {
      conflictField = 'relation';
      conflictOld = oldRel;
      conflictNew = h.relation;
    } else if (h.phone != null && _meaningfullyDifferent(oldPhone, h.phone)) {
      conflictField = 'phone';
      conflictOld = oldPhone;
      conflictNew = h.phone;
    } else if (h.note != null &&
        h.note!.trim().isNotEmpty &&
        _meaningfullyDifferent(oldNote, h.note!.trim())) {
      conflictField = 'note';
      conflictOld = oldNote;
      conflictNew = h.note!.trim();
    }

    if (conflictField != null) {
      await LocalDatabase.insertRelationConflict(
        id: _newId('rc'),
        ownerUserId: _activeUserId,
        personName: h.name.trim(),
        fieldName: conflictField,
        nearbyPersonId: id,
        oldValue: conflictOld,
        newValue: conflictNew,
        sourceMessageId: sourceMessageId,
      );
    }

    Future<Map<String, dynamic>?> freshNearbyRow() async {
      final rows = await LocalDatabase.getNearbyPeopleForUser(_activeUserId);
      for (final r in rows) {
        if (r['id'] == id) return r;
      }
      return null;
    }

    if (h.relation != null) {
      if (!_meaningfullyDifferent(oldRel, h.relation) &&
          (oldRel ?? '').trim().isEmpty) {
        final cur = await freshNearbyRow();
        if (cur != null) {
          await LocalDatabase.upsertNearbyPerson({
            ...cur,
            'relation': h.relation,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }

    if (h.phone != null) {
      if (!_meaningfullyDifferent(oldPhone, h.phone) &&
          (oldPhone ?? '').trim().isEmpty) {
        final cur = await freshNearbyRow();
        if (cur != null) {
          await LocalDatabase.upsertNearbyPerson({
            ...cur,
            'phone': h.phone,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }

    if (h.note != null && h.note!.trim().isNotEmpty) {
      final n = h.note!.trim();
      if (!_meaningfullyDifferent(oldNote, n) &&
          (oldNote ?? '').trim().isEmpty) {
        final cur = await freshNearbyRow();
        if (cur != null) {
          await LocalDatabase.upsertNearbyPerson({
            ...cur,
            'note': n,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }
  }

  Future<void> _saveMessage(ChatMessage message) async {
    await LocalDatabase.insertMessage({
      'id': message.id,
      'conversation_id': _activeConversationId,
      'user_id': message.isUser ? _activeUserId : null,
      'content': message.content,
      'type': message.kind.name,
      'timestamp': message.timestamp.toIso8601String(),
      'extra': json.encode({
        'is_user': message.isUser,
        'title': message.title,
        'options': message.options,
        'cue_label': message.cueLabel,
        'image_path': message.imagePath,
        'profile_photo_id': message.profilePhotoId,
      }),
    });
  }

  Future<void> _trySaveMessage(ChatMessage message) async {
    try {
      await _saveMessage(message);
    } catch (_) {
      // Keep UI available even when local DB is temporarily unavailable.
    }
  }

  ChatMessage _chatMessageFromRow(Map<String, dynamic> row) {
    final extra = LocalDatabase.decodeJson(row['extra'] as String?)
            as Map<String, dynamic>? ??
        <String, dynamic>{};
    final kindName = row['type'] as String?;
    final kind = ChatMessageKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => ChatMessageKind.text,
    );
    return ChatMessage(
      id: row['id'] as String,
      content: row['content'] as String? ?? '',
      isUser: extra['is_user'] as bool? ?? false,
      timestamp: DateTime.tryParse(row['timestamp'] as String? ?? '') ??
          DateTime.now(),
      kind: kind,
      title: extra['title'] as String?,
      cueLabel: extra['cue_label'] as String?,
      options: (extra['options'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      imagePath: extra['image_path'] as String?,
      profilePhotoId: extra['profile_photo_id'] as String?,
    );
  }

  @override
  void dispose() {
    LocalDatabase.close();
    super.dispose();
  }
}
