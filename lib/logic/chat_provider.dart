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
import 'relation_extractor.dart';

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

  bool get isSending => _isSending;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  String get activeUserId => _activeUserId;

  String get activeConversationId => _activeConversationId;

  List<RelationConflictRecord> get pendingRelationConflicts =>
      List.unmodifiable(_pendingConflicts);

  Future<void> sendMessage(String content) async {
    await _initFuture;
    final text = content.trim();
    if (text.isEmpty || _isSending) return;

    _userTurnCount += 1;
    final userMessage = _textMessage(content: text, isUser: true);
    _messages.add(userMessage);
    await _trySaveMessage(userMessage);
    _isSending = true;
    notifyListeners();

    try {
      final reply = await _repository
          .sendMessage(
            history: _messages,
            systemPrompt: await _buildSystemPromptAsync(),
          )
          .timeout(const Duration(seconds: 110));
      final assistantMessage = _textMessage(content: reply, isUser: false);
      _messages.add(assistantMessage);
      await _trySaveMessage(assistantMessage);
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

  Future<String> _memoryBulletsForPrompt() async {
    try {
      final user = await LocalDatabase.getUserById(_activeUserId);
      final userLabel = (user?['name'] as String?)?.trim();
      final rows = await LocalDatabase.getNearbyPeopleForUser(_activeUserId);
      final lines = <String>[];
      if (userLabel != null && userLabel.isNotEmpty) {
        lines.add('- 用户称呼：$userLabel。');
      }
      if (user != null) {
        const profilePairs = <String, String>{
          'birth_year': '出生年月',
          'hometown': '籍贯',
          'career': '职业经历',
          'hobbies': '兴趣爱好',
          'food_preference': '饮食习惯',
          'personality': '性格',
          'taboo': '忌讳话题',
          'dialect': '方言',
        };
        for (final e in profilePairs.entries) {
          final v = (user[e.key] as String?)?.trim();
          if (v != null && v.isNotEmpty) {
            lines.add('- 老人档案·${e.value}：$v');
          }
        }
      }

      final familyRows =
          await LocalDatabase.listFamilyMembersForUser(_activeUserId);
      if (familyRows.isEmpty) {
        lines.add('- 家庭成员表：暂无结构化记录。');
      } else {
        for (final r in familyRows.take(10)) {
          final name = (r['name'] as String?)?.trim() ?? '（姓名未填）';
          final rel = (r['relation'] as String?)?.trim() ?? '';
          final loc = (r['location'] as String?)?.trim() ?? '';
          final notes = (r['notes'] as String?)?.trim() ?? '';
          final active = ((r['is_active'] as int?) ?? 1) != 0;
          lines.add(
            '- 家人：${rel.isEmpty ? '亲属' : rel} $name'
            '${active ? '' : '（已故）'}'
            '${loc.isEmpty ? '' : '，住$loc'}'
            '${notes.isEmpty ? '' : '；$notes'}',
          );
        }
      }

      final memRows = await LocalDatabase.listMemoryEventsForUser(
        _activeUserId,
        limit: 8,
      );
      if (memRows.isEmpty) {
        lines.add('- 往事记忆库：暂无已保存事件。');
      } else {
        for (final r in memRows) {
          final t = (r['title'] as String?)?.trim() ?? '';
          final et = (r['event_time'] as String?)?.trim() ?? '';
          if (t.isEmpty) continue;
          lines.add(
            '- 往事：${et.isEmpty ? '' : '$et · '}$t',
          );
        }
      }

      final dailyRows = await LocalDatabase.listDailyLifeRecordsForUser(
        _activeUserId,
        limit: 4,
      );
      if (dailyRows.isEmpty) {
        lines.add('- 每日生活记录：暂无。');
      } else {
        for (final r in dailyRows) {
          final d = (r['date'] as String?)?.trim() ?? '';
          final parts = <String>[];
          void add(String label, String col) {
            final v = (r[col] as String?)?.trim();
            if (v != null && v.isNotEmpty) parts.add('$label$v');
          }

          add('早', 'breakfast');
          add('午', 'lunch');
          add('晚', 'dinner');
          add('活动', 'activities');
          add('心情', 'mood');
          if (parts.isEmpty) continue;
          lines.add('- $d 日常：${parts.join('；')}');
        }
      }

      if (rows.isEmpty) {
        lines.add('- 周围人（邻居/朋友等）档案：暂无已保存条目，可引导老人慢慢介绍亲友。');
      } else {
        for (final r in rows) {
          final name = (r['name'] as String?)?.trim() ?? '（未写姓名）';
          final rel = (r['relation'] as String?)?.trim() ?? '';
          final phone = (r['phone'] as String?)?.trim() ?? '';
          final note = (r['note'] as String?)?.trim() ?? '';
          lines.add(
            '- ${rel.isEmpty ? '亲友' : rel}：$name'
            '${phone.isEmpty ? '' : '，电话 $phone'}'
            '${note.isEmpty ? '' : '；$note'}',
          );
        }
      }
      return lines.join('\n');
    } catch (_) {
      return '- （读取本地记忆资料失败，仍可陪老人聊天。）';
    }
  }

  Future<String> _buildSystemPromptAsync() async {
    final memory = await _memoryBulletsForPrompt();
    return '''
你是“拾忆”，一款面向阿尔兹海默症早期老人、MCI阶段老人、健忘老人和空巢老人的陪伴关怀助手。

你的目标：
1. 像耐心、温暖、可信的老朋友一样陪老人说话。
2. 老人随口提到事情时，优先联系「已有记忆资料」，自然追问，帮助扩充记忆资料。
3. 在话题自然停顿时，用提问型方式开启和老人记忆相关的新话题。
4. 适时加入轻量认知干预，例如识别人、日常物品、地点、天气、旧职业、亲友关系，但语气必须像聊天，不能像考试。
5. 不做医疗诊断，不使用“病情、治疗、评估结果”等医学结论。

已有记忆资料：
$memory

当老人说的亲友姓名、称谓或经历与上面档案不一致时：
- 不要生硬否定，也不要替老人断定「记错了」。
- 先温和厘清：是家里不止一位（例如两个女儿）还是同一位、名字或说法前后不一样。
- 若老人确认是同一人，以老人最新说法为准，自然接话，不要提技术词。

回复规则：
- 每次回复控制在2到4句话。
- 先回应情绪，再轻轻追问。
- 追问一次即可，不要连珠炮。
- 如果老人记不清，要安慰：“没关系，我们慢慢想”。
- 语言使用自然中文，不要机械，不要提“数据库、认知干预、模型”等词。
''';
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
      return '请在电脑上先启动本地代理：在项目目录运行 `python server/local_chat_server.py`（需配置 VIVO_APP_KEY），并确认地址为 ${AppConstants.apiBaseUrl}。';
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
    } catch (_) {
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
        final fullText =
            transcript.map((e) => e['content'] ?? '').join('\n');
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
      add('出生年月', 'birth_year');
      add('籍贯', 'hometown');
      add('职业经历', 'career');
      add('兴趣爱好', 'hobbies');
      add('饮食习惯', 'food_preference');
      add('性格', 'personality');
      add('忌讳', 'taboo');
      add('方言', 'dialect');
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

  bool _meaningfullyDifferentPersonName(String? a, String? b) {
    final x = LocalDatabase.normalizePersonName(a);
    final y = LocalDatabase.normalizePersonName(b);
    if (x.length < 2 || y.length < 2) return false;
    return x != y;
  }

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

    final srk = LocalDatabase.normalizeRelationLabel(h.sameRelationKey);
    final relNorm = LocalDatabase.normalizeRelationLabel(h.relation);
    final slot = srk.isNotEmpty ? srk : relNorm;
    if (slot.isEmpty) return null;

    final candidates = await LocalDatabase.findNearbyPeopleByNormalizedRelation(
      _activeUserId,
      slot,
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
      if (!_meaningfullyDifferent(oldNote, n) && (oldNote ?? '').trim().isEmpty) {
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
    );
  }

  @override
  void dispose() {
    LocalDatabase.close();
    super.dispose();
  }
}
