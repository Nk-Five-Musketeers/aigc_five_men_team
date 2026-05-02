import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../local_db/local_database.dart';
import '../models/chat_message.dart';
import '../models/daily_note.dart';
import '../models/memory_item.dart';
import '../models/story_item.dart';

class MemoryRepository {
  static final Map<String, Object?> _fallbackProfile = <String, Object?>{
    'id': 1,
  };
  static final List<Map<String, Object?>> _fallbackFamilyMembers =
      <Map<String, Object?>>[];
  static final List<MemoryItem> _fallbackMemories = <MemoryItem>[];
  static final List<DailyNote> _fallbackDailyRecords = <DailyNote>[];
  static final List<ChatMessage> _fallbackMessages = <ChatMessage>[];

  Future<List<StoryItem>> fetchStories() async {
    final memories = await fetchRecentMemories(limit: 12);
    return memories
        .map(
          (item) => StoryItem(
            id: item.id,
            title: item.title,
            description: item.description,
            createdAt: item.createdAt,
          ),
        )
        .toList();
  }

  Future<void> saveElderProfile(Map<String, Object?> updates) async {
    if (updates.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final row = <String, Object?>{
      'id': 1,
      'created_at': updates['created_at'] ?? now,
      'updated_at': updates['updated_at'] ?? now,
      ...updates,
    };

    final db = await LocalDatabase.tryInstance();
    if (db == null) {
      _fallbackProfile.addAll(row);
      return;
    }

    try {
      final existing = await db.query(
        'elder_basic_info',
        where: 'id = ?',
        whereArgs: const <Object?>[1],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('elder_basic_info', row);
      } else {
        final merged = <String, Object?>{...existing.first, ...row};
        await db.update(
          'elder_basic_info',
          merged,
          where: 'id = ?',
          whereArgs: const <Object?>[1],
        );
      }
    } catch (_) {
      _fallbackProfile.addAll(row);
    }
  }

  Future<void> saveFamilyMembers(List<Map<String, Object?>> members) async {
    for (final member in members) {
      await saveFamilyMember(member);
    }
  }

  Future<void> saveFamilyMember(Map<String, Object?> member) async {
    final name = member['name']?.toString().trim();
    if (name == null || name.isEmpty) return;

    final db = await LocalDatabase.tryInstance();
    if (db == null) {
      _saveFallbackFamilyMember(member);
      return;
    }

    try {
      final existing = await db.query(
        'family_members',
        where: 'name = ?',
        whereArgs: <Object?>[name],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert(
          'family_members',
          member,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final merged = <String, Object?>{...existing.first, ...member};
        merged['id'] = existing.first['id'];
        await db.update(
          'family_members',
          merged,
          where: 'id = ?',
          whereArgs: <Object?>[existing.first['id']],
        );
      }
    } catch (_) {
      _saveFallbackFamilyMember(member);
    }
  }

  Future<void> saveChatMessage(ChatMessage message) async {
    final row = _conversationRowFromMessage(message);
    final db = await LocalDatabase.tryInstance();
    if (db == null) {
      _saveFallbackMessage(message);
      return;
    }

    try {
      await db.insert(
        'conversation_records',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      _saveFallbackMessage(message);
    }
  }

  Future<List<ChatMessage>> fetchChatMessages({int limit = 80}) async {
    final db = await LocalDatabase.tryInstance();
    if (db == null) return _fetchFallbackMessages(limit);

    try {
      final rows = await db.query(
        'conversation_records',
        orderBy: 'session_date DESC',
        limit: limit,
      );

      return rows.reversed.map(_messageFromConversationRow).toList();
    } catch (_) {
      return _fetchFallbackMessages(limit);
    }
  }

  Future<void> saveMemoryItems(List<MemoryItem> items) async {
    for (final item in items) {
      await saveMemoryItem(item);
    }
  }

  Future<void> saveMemoryItem(MemoryItem item) async {
    final existing = await _findSimilarMemory(item);
    final itemToSave = existing == null ? item : _mergeMemory(existing, item);

    final db = await LocalDatabase.tryInstance();
    if (db == null) {
      _saveFallbackMemory(itemToSave);
      return;
    }

    try {
      await db.insert(
        'memory_events',
        itemToSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      _saveFallbackMemory(itemToSave);
    }
  }

  Future<List<MemoryItem>> fetchRecentMemories({int limit = 12}) async {
    final db = await LocalDatabase.tryInstance();
    if (db == null) return _fetchFallbackMemories(limit);

    try {
      final rows = await db.query(
        'memory_events',
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      return rows.map(MemoryItem.fromMap).toList();
    } catch (_) {
      return _fetchFallbackMemories(limit);
    }
  }

  Future<List<MemoryItem>> searchMemories(String text, {int limit = 6}) async {
    final recent = await fetchRecentMemories(limit: 80);
    final scored = recent
        .map((item) => _ScoredMemory(item, _scoreMemory(item, text)))
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.take(limit).map((item) => item.memory).toList();
  }

  Future<String> buildMemoryContext(String latestText, {int limit = 6}) async {
    final profile = await fetchElderProfile();
    final family = await fetchFamilyMembers(limit: 6);
    final matched = await searchMemories(latestText, limit: limit);
    final memories = matched.isNotEmpty ? matched : await fetchRecentMemories(limit: limit);

    final lines = <String>[];
    if (profile.isNotEmpty) {
      lines.add(
        '老人基本信息：${_compactMap(profile, const <String>{'id', 'created_at', 'updated_at'})}',
      );
    }
    if (family.isNotEmpty) {
      lines.add(
        '亲戚朋友：${family.map((item) => _compactMap(item, const <String>{'id', 'created_at', 'updated_at'})).join('；')}',
      );
    }
    for (final item in memories) {
      lines.add(
        '记忆事件：${item.title}：${item.description}（时间：${item.eventTime ?? '未明确'}，地点：${item.location ?? '未明确'}，人物：${item.peopleInvolved ?? '未明确'}，重要度${item.importance}）',
      );
    }

    return lines.join('\n');
  }

  Future<Map<String, Object?>> fetchElderProfile() async {
    final db = await LocalDatabase.tryInstance();
    if (db == null) return Map<String, Object?>.from(_fallbackProfile);

    try {
      final rows = await db.query(
        'elder_basic_info',
        where: 'id = ?',
        whereArgs: const <Object?>[1],
        limit: 1,
      );
      return rows.isEmpty ? <String, Object?>{} : Map<String, Object?>.from(rows.first);
    } catch (_) {
      return Map<String, Object?>.from(_fallbackProfile);
    }
  }

  Future<List<Map<String, Object?>>> fetchFamilyMembers({int limit = 20}) async {
    final db = await LocalDatabase.tryInstance();
    if (db == null) {
      return _fallbackFamilyMembers
          .take(limit)
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    }

    try {
      final rows = await db.query(
        'family_members',
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      return rows.map((item) => Map<String, Object?>.from(item)).toList();
    } catch (_) {
      return _fallbackFamilyMembers
          .take(limit)
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    }
  }

  Future<void> saveDailyNote(DailyNote note) async {
    final db = await LocalDatabase.tryInstance();
    if (db == null) {
      _saveFallbackDailyRecord(note);
      return;
    }

    try {
      await db.insert(
        'daily_life_records',
        note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      _saveFallbackDailyRecord(note);
    }
  }

  Future<List<DailyNote>> fetchDailyNotes({int limit = 20}) async {
    final db = await LocalDatabase.tryInstance();
    if (db == null) return _fetchFallbackDailyRecords(limit);

    try {
      final rows = await db.query(
        'daily_life_records',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return rows.map(DailyNote.fromMap).toList();
    } catch (_) {
      return _fetchFallbackDailyRecords(limit);
    }
  }

  Future<MemoryItem?> _findSimilarMemory(MemoryItem item) async {
    final db = await LocalDatabase.tryInstance();
    if (db == null) {
      for (final memory in _fallbackMemories) {
        if (memory.title == item.title) return memory;
      }
      return null;
    }

    try {
      final rows = await db.query(
        'memory_events',
        where: 'title = ?',
        whereArgs: <Object?>[item.title],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return MemoryItem.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _conversationRowFromMessage(ChatMessage message) {
    final now = DateTime.now().toIso8601String();
    return <String, Object?>{
      'id': message.timestamp.microsecondsSinceEpoch,
      'session_date': message.timestamp.toIso8601String(),
      'duration': 0,
      'dialog_json': jsonEncode(_messageToMap(message)),
      'new_memories': null,
      'cognitive_score': null,
      'quiz_results': null,
      'processed': 0,
      'created_at': now,
      'updated_at': now,
    };
  }

  void _saveFallbackFamilyMember(Map<String, Object?> member) {
    final name = member['name']?.toString();
    final index = _fallbackFamilyMembers.indexWhere((item) => item['name'] == name);
    if (index >= 0) {
      _fallbackFamilyMembers[index] = <String, Object?>{
        ..._fallbackFamilyMembers[index],
        ...member,
      };
    } else {
      _fallbackFamilyMembers.add(member);
    }
  }

  void _saveFallbackMessage(ChatMessage message) {
    final index = _fallbackMessages.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      _fallbackMessages[index] = message;
    } else {
      _fallbackMessages.add(message);
    }
  }

  List<ChatMessage> _fetchFallbackMessages(int limit) {
    if (_fallbackMessages.length <= limit) {
      return List<ChatMessage>.from(_fallbackMessages);
    }
    return _fallbackMessages.sublist(_fallbackMessages.length - limit);
  }

  void _saveFallbackMemory(MemoryItem item) {
    final index = _fallbackMemories.indexWhere((memory) => memory.title == item.title);
    if (index >= 0) {
      _fallbackMemories[index] = _mergeMemory(_fallbackMemories[index], item);
    } else {
      _fallbackMemories.add(item);
    }
  }

  List<MemoryItem> _fetchFallbackMemories(int limit) {
    final items = List<MemoryItem>.from(_fallbackMemories)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.take(limit).toList();
  }

  void _saveFallbackDailyRecord(DailyNote note) {
    final index = _fallbackDailyRecords.indexWhere((item) => item.id == note.id);
    if (index >= 0) {
      _fallbackDailyRecords[index] = note;
    } else {
      _fallbackDailyRecords.add(note);
    }
  }

  List<DailyNote> _fetchFallbackDailyRecords(int limit) {
    final items = List<DailyNote>.from(_fallbackDailyRecords)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items.take(limit).toList();
  }

  MemoryItem _mergeMemory(MemoryItem oldItem, MemoryItem newItem) {
    final description = oldItem.description.contains(newItem.description)
        ? oldItem.description
        : _trimDescription('${oldItem.description}；${newItem.description}');

    return MemoryItem(
      id: oldItem.id,
      eventTime: oldItem.eventTime ?? newItem.eventTime,
      title: oldItem.title,
      description: description,
      location: oldItem.location ?? newItem.location,
      peopleInvolved: oldItem.peopleInvolved ?? newItem.peopleInvolved,
      emotion: oldItem.emotion ?? newItem.emotion,
      photoPaths: oldItem.photoPaths ?? newItem.photoPaths,
      videoPath: oldItem.videoPath ?? newItem.videoPath,
      importance: oldItem.importance > newItem.importance
          ? oldItem.importance
          : newItem.importance,
      source: oldItem.source ?? newItem.source,
      verified: oldItem.verified || newItem.verified,
      usedCount: oldItem.usedCount,
      lastUsed: oldItem.lastUsed,
      sourceDialog: oldItem.sourceDialog ?? newItem.sourceDialog,
      createdAt: oldItem.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  String _trimDescription(String value) {
    if (value.length <= 500) return value;
    return value.substring(value.length - 500);
  }

  int _scoreMemory(MemoryItem item, String text) {
    var score = 0;
    for (final keyword in item.keywords) {
      if (keyword.isNotEmpty && text.contains(keyword)) score += 3;
    }
    if (text.contains(item.title)) score += 4;
    if (item.description.contains(text) || text.contains(item.description)) score += 2;
    return score;
  }

  String _compactMap(Map<String, Object?> map, Set<String> ignoredKeys) {
    return map.entries
        .where((entry) => !ignoredKeys.contains(entry.key))
        .where((entry) {
          final value = entry.value;
          return value != null && value.toString().trim().isNotEmpty;
        })
        .map((entry) => '${entry.key}:${entry.value}')
        .join('，');
  }

  Map<String, Object?> _messageToMap(ChatMessage message) {
    return <String, Object?>{
      'id': message.id,
      'content': message.content,
      'is_user': message.isUser,
      'timestamp': message.timestamp.toIso8601String(),
      'kind': message.kind.name,
      'title': message.title,
      'cue_label': message.cueLabel,
      'options': message.options,
    };
  }

  ChatMessage _messageFromConversationRow(Map<String, Object?> map) {
    final dialog = jsonDecode(map['dialog_json'] as String);
    if (dialog is! Map<String, dynamic>) {
      throw StateError('Invalid dialog_json');
    }
    return _messageFromMap(dialog);
  }

  ChatMessage _messageFromMap(Map<String, Object?> map) {
    return ChatMessage(
      id: map['id'] as String,
      content: map['content'] as String,
      isUser: map['is_user'] == true || map['is_user'] == 1,
      timestamp: DateTime.parse(map['timestamp'] as String),
      kind: _kindFromName(map['kind'] as String?),
      title: map['title'] as String?,
      cueLabel: map['cue_label'] as String?,
      options: _decodeOptions(map['options']),
    );
  }

  ChatMessageKind _kindFromName(String? value) {
    return ChatMessageKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => ChatMessageKind.text,
    );
  }

  List<String> _decodeOptions(Object? value) {
    if (value is List) return value.whereType<String>().toList();
    if (value is! String || value.isEmpty) return const <String>[];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const <String>[];
    return decoded.whereType<String>().toList();
  }
}

class _ScoredMemory {
  _ScoredMemory(this.memory, this.score);

  final MemoryItem memory;
  final int score;
}
