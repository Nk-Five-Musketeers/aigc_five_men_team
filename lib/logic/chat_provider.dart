import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../data/models/chat_message.dart';
import '../data/models/extracted_relation_hint.dart';
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
            promptContext: await _buildPromptContextAsync(),
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
      if (rows.isEmpty) {
        lines.add('- 周围人档案：暂无已保存条目，可引导老人慢慢介绍亲友。');
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

  /// 与 `server/prompts` 中全局模块对齐；记忆摘要来自本地库。
  Future<Map<String, dynamic>> _buildPromptContextAsync() async {
    final memoryText = await _memoryBulletsForPrompt();
    final snippets = memoryText
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return <String, dynamic>{
      'global': <String, dynamic>{
        'dialect_preference': 0.65,
        'response_style': '简短温柔',
        'sensitive_topics': <String>[],
        'memory_snippets': snippets,
      },
    };
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
      var hints = <ExtractedRelationHint>[];

      try {
        hints = await _repository
            .extractRelationsFromChat(
              transcriptMessages: transcript,
              existingNearbySummary: nearbySummary,
            )
            .timeout(const Duration(seconds: 50));
        llmHintCount = hints.length;
      } catch (e, st) {
        debugPrint('[relation_extract] LLM 调用失败: $e\n$st');
      }

      if (hints.isEmpty) {
        final fullText =
            transcript.map((e) => e['content'] ?? '').join('\n');
        hints = RelationExtractor.extract(fullText);
        ruleHintCount = hints.length;
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

  List<Map<String, String>> _buildExtractionTranscript() {
    final normal = _messages
        .where(
          (m) =>
              m.kind == ChatMessageKind.text || m.kind == ChatMessageKind.error,
        )
        .toList();
    final recent =
        normal.length > 14 ? normal.sublist(normal.length - 14) : normal;
    return recent
        .map(
          (m) => <String, String>{
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.content,
          },
        )
        .toList();
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
      ExtractedRelationHint h) async {
    final norm = LocalDatabase.normalizePersonName(h.name);
    if (norm.length < 2) return null;

    final byName = await LocalDatabase.findNearbyPersonByNormalizedName(
      _activeUserId,
      norm,
    );
    if (byName != null) return byName;

    final srk =
        LocalDatabase.normalizeRelationLabel(h.sameRelationKey);
    final relNorm = LocalDatabase.normalizeRelationLabel(h.relation);
    final slot = srk.isNotEmpty ? srk : relNorm;
    if (slot.isEmpty) return null;

    final candidates =
        await LocalDatabase.findNearbyPeopleByNormalizedRelation(
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

    if (_meaningfullyDifferentPersonName(oldName, h.name)) {
      await LocalDatabase.insertRelationConflict(
        id: _newId('rc'),
        ownerUserId: _activeUserId,
        personName: h.name.trim(),
        fieldName: 'name',
        nearbyPersonId: id,
        oldValue: oldName,
        newValue: h.name.trim(),
        sourceMessageId: sourceMessageId,
      );
    }

    if (h.relation != null) {
      if (_meaningfullyDifferent(oldRel, h.relation)) {
        await LocalDatabase.insertRelationConflict(
          id: _newId('rc'),
          ownerUserId: _activeUserId,
          personName: h.name.trim(),
          fieldName: 'relation',
          nearbyPersonId: id,
          oldValue: oldRel,
          newValue: h.relation,
          sourceMessageId: sourceMessageId,
        );
      } else if ((oldRel ?? '').trim().isEmpty) {
        await LocalDatabase.upsertNearbyPerson({
          ...existing,
          'relation': h.relation,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    }

    if (h.phone != null) {
      if (_meaningfullyDifferent(oldPhone, h.phone)) {
        await LocalDatabase.insertRelationConflict(
          id: _newId('rc'),
          ownerUserId: _activeUserId,
          personName: h.name.trim(),
          fieldName: 'phone',
          nearbyPersonId: id,
          oldValue: oldPhone,
          newValue: h.phone,
          sourceMessageId: sourceMessageId,
        );
      } else if ((oldPhone ?? '').trim().isEmpty) {
        await LocalDatabase.upsertNearbyPerson({
          ...existing,
          'phone': h.phone,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    }

    if (h.note != null && h.note!.trim().isNotEmpty) {
      final n = h.note!.trim();
      if ((oldNote ?? '').trim().isEmpty) {
        await LocalDatabase.upsertNearbyPerson({
          ...existing,
          'note': n,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else if (_meaningfullyDifferent(oldNote, n)) {
        await LocalDatabase.insertRelationConflict(
          id: _newId('rc'),
          ownerUserId: _activeUserId,
          personName: h.name.trim(),
          fieldName: 'note',
          nearbyPersonId: id,
          oldValue: oldNote,
          newValue: n,
          sourceMessageId: sourceMessageId,
        );
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
