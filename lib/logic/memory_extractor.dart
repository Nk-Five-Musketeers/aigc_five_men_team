import 'dart:convert';

import '../config/constants.dart';
import '../core/api_client.dart';
import '../data/models/daily_note.dart';
import '../data/models/memory_item.dart';

class MemoryExtractionResult {
  const MemoryExtractionResult({
    required this.elderProfile,
    required this.familyMembers,
    required this.memoryEvents,
    this.dailyRecord,
  });

  final Map<String, Object?> elderProfile;
  final List<Map<String, Object?>> familyMembers;
  final List<MemoryItem> memoryEvents;
  final DailyNote? dailyRecord;

  bool get hasUpdates {
    return elderProfile.isNotEmpty ||
        familyMembers.isNotEmpty ||
        memoryEvents.isNotEmpty ||
        dailyRecord != null;
  }
}

class MemoryExtractor {
  MemoryExtractor({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<MemoryExtractionResult> extractFromUserText({
    required String text,
    required String sourceMessageId,
    String conversationContext = '',
    DateTime? now,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return _emptyResult;

    try {
      final createdAt = now ?? DateTime.now();
      final rawJson = await _requestExtractionJson(
        normalized,
        createdAt,
        conversationContext,
      );
      return _parseExtraction(
        rawJson: rawJson,
        sourceText: normalized,
        sourceMessageId: sourceMessageId,
        createdAt: createdAt,
      );
    } catch (_) {
      return _emptyResult;
    }
  }

  Future<String> _requestExtractionJson(
    String text,
    DateTime now,
    String conversationContext,
  ) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: <String, Object?>{
        'model': AppConstants.modelId,
        'temperature': 0.1,
        'top_p': 0.5,
        'max_tokens': 1400,
        'reasoning_effort': 'minimal',
        'enable_thinking': false,
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': _extractionSystemPrompt,
          },
          <String, String>{
            'role': 'user',
            'content': '''
当前时间：${now.toIso8601String()}
近期上下文：
${conversationContext.trim().isEmpty ? '无' : conversationContext}

老人本轮输入：
$text
''',
          },
        ],
      },
    );

    final choices = response.data?['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String && content.trim().isNotEmpty) {
            return content.trim();
          }
        }
      }
    }
    throw StateError('Empty extraction response');
  }

  MemoryExtractionResult _parseExtraction({
    required String rawJson,
    required String sourceText,
    required String sourceMessageId,
    required DateTime createdAt,
  }) {
    final decoded = jsonDecode(_extractJsonObject(rawJson));
    if (decoded is! Map<String, dynamic>) return _emptyResult;

    final profile = _parseProfile(decoded['elder_basic_info'], createdAt);
    final familyMembers = _parseFamilyMembers(
      decoded['family_members'],
      sourceMessageId,
      createdAt,
    );
    final memoryEvents = _parseMemoryEvents(
      decoded['memory_events'],
      sourceMessageId,
      createdAt,
    );
    final dailyRecord = _parseDailyRecord(
      decoded['daily_life_record'],
      sourceText,
      sourceMessageId,
      createdAt,
    );

    return MemoryExtractionResult(
      elderProfile: profile,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyRecord: dailyRecord,
    );
  }

  Map<String, Object?> _parseProfile(Object? raw, DateTime now) {
    if (raw is! Map || raw['should_save'] == false) return <String, Object?>{};
    final item = Map<String, dynamic>.from(raw);
    final profile = <String, Object?>{
      'id': 1,
      'updated_at': now.toIso8601String(),
    };

    const fields = <String>[
      'name',
      'birth_year',
      'hometown',
      'career',
      'hobbies',
      'food_preference',
      'personality',
      'taboo',
      'dialect',
      'avatar_path',
    ];
    for (final field in fields) {
      final value = _readNullableString(item[field]);
      if (value != null) profile[field] = value;
    }

    return profile.length <= 2 ? <String, Object?>{} : profile;
  }

  List<Map<String, Object?>> _parseFamilyMembers(
    Object? raw,
    String sourceMessageId,
    DateTime now,
  ) {
    if (raw is! List) return const <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];

    for (final rawItem in raw) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      if (item['should_save'] == false) continue;
      final name = _readNullableString(item['name']);
      if (name == null) continue;

      result.add(<String, Object?>{
        'id': int.parse(_newId()),
        'name': name,
        'relation': _readNullableString(item['relation']),
        'photo_path': _readNullableString(item['photo_path']),
        'birthday': _readNullableString(item['birthday']),
        'location': _readNullableString(item['location']),
        'contact_freq': _readNullableString(item['contact_freq']),
        'notes': _readNullableString(item['notes']),
        'is_active': _readBool(item['is_active'], fallback: true) ? 1 : 0,
        'source_dialog': sourceMessageId,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }

    return result;
  }

  List<MemoryItem> _parseMemoryEvents(
    Object? raw,
    String sourceMessageId,
    DateTime now,
  ) {
    if (raw is! List) return const <MemoryItem>[];
    final result = <MemoryItem>[];

    for (final rawItem in raw) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      if (item['should_save'] == false) continue;

      final title = _readNullableString(item['title']);
      final description = _readNullableString(item['description']);
      if (title == null || description == null) continue;

      result.add(
        MemoryItem(
          id: _newId(),
          eventTime: _readNullableString(item['event_time']),
          title: title,
          description: description,
          location: _readNullableString(item['location']),
          peopleInvolved: _readNullableString(item['people_involved']),
          emotion: _readNullableString(item['emotion']),
          photoPaths: _readNullableString(item['photo_paths']),
          videoPath: _readNullableString(item['video_path']),
          importance: _clampInt(item['importance'], fallback: 3),
          source: _readNullableString(item['source']) ?? 'AI提取',
          verified: _readBool(item['verified'], fallback: false),
          usedCount: 0,
          lastUsed: null,
          sourceDialog: sourceMessageId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    return result;
  }

  DailyNote? _parseDailyRecord(
    Object? raw,
    String sourceText,
    String sourceMessageId,
    DateTime now,
  ) {
    if (raw is! Map || raw['should_save'] == false) return null;
    final item = Map<String, dynamic>.from(raw);
    final record = DailyNote(
      id: _newId(),
      date: _readNullableString(item['date']) ?? _dateOnly(now),
      breakfast: _readNullableString(item['breakfast']),
      lunch: _readNullableString(item['lunch']),
      dinner: _readNullableString(item['dinner']),
      activities: _readNullableString(item['activities']),
      peopleMet: _readNullableString(item['people_met']),
      placesWent: _readNullableString(item['places_went']),
      mood: _readNullableString(item['mood']),
      rawExtract: _readNullableString(item['raw_extract']) ?? sourceText,
      sourceDialog: sourceMessageId,
      createdAt: now,
      updatedAt: now,
    );

    final map = record.toMap();
    final hasAnyValue = map.entries.any((entry) {
      if (<String>{'id', 'date', 'raw_extract', 'source_dialog', 'created_at', 'updated_at'}
          .contains(entry.key)) {
        return false;
      }
      final value = entry.value;
      return value is String && value.trim().isNotEmpty;
    });
    return hasAnyValue || (record.rawExtract?.trim().isNotEmpty ?? false) ? record : null;
  }

  String _extractJsonObject(String value) {
    var text = value.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceAll(RegExp(r'\s*```$'), '');
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return text;
    return text.substring(start, end + 1);
  }

  String? _readNullableString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  bool _readBool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == 'true' || value == '是' || value == '1';
    return fallback;
  }

  int _clampInt(Object? value, {required int fallback}) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) return fallback;
    if (parsed < 1) return 1;
    if (parsed > 5) return 5;
    return parsed;
  }

  String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _newId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}

const MemoryExtractionResult _emptyResult = MemoryExtractionResult(
  elderProfile: <String, Object?>{},
  familyMembers: <Map<String, Object?>>[],
  memoryEvents: <MemoryItem>[],
);

const String _extractionSystemPrompt = '''
你是“拾忆”App 的本地记忆整理员。你的任务不是陪聊，而是判断老人本轮输入是否值得补充到本地数据库的五张表中。

请只输出一个 JSON 对象，不要 Markdown，不要解释，不要多余文本。

五张表：
1. elder_basic_info：老人基本信息表。
2. family_members：亲戚朋友/家庭成员表。
3. memory_events：记忆事件库，核心表，用于后续生成老人传记。
4. daily_life_record：每日生活记录表。
5. conversation_records：对话记录表由 App 自动保存，你不要输出这一表。

保存原则：
- 只有有价值、可复用、可追问、可照护参考的信息才保存。
- 不要因为普通寒暄保存。
- 不要编造老人没有说过的信息。
- 不确定的信息 verified=false。
- 如果老人说的是“有点冷”“那是我女儿”“院子里有水缸”等短回答，要结合近期上下文判断是否能补充记忆事件。
- 不要做医学诊断，只做生活记录和温和观察。
- 如果没有任何值得保存的信息，所有表返回空或 null。

输出格式必须严格如下：
{
  "elder_basic_info": {
    "should_save": false,
    "name": null,
    "birth_year": null,
    "hometown": null,
    "career": null,
    "hobbies": null,
    "food_preference": null,
    "personality": null,
    "taboo": null,
    "dialect": null,
    "avatar_path": null
  },
  "family_members": [
    {
      "should_save": true,
      "name": "成员姓名",
      "relation": "与老人关系",
      "photo_path": null,
      "birthday": null,
      "location": null,
      "contact_freq": null,
      "notes": "备注",
      "is_active": true
    }
  ],
  "memory_events": [
    {
      "should_save": true,
      "event_time": "事件发生时间",
      "title": "事件标题",
      "description": "详细描述，忠于老人原话",
      "location": "发生地点",
      "people_involved": "涉及人物",
      "emotion": "老人情感态度",
      "photo_paths": null,
      "video_path": null,
      "importance": 1,
      "source": "AI提取",
      "verified": false
    }
  ],
  "daily_life_record": {
    "should_save": true,
    "date": "YYYY-MM-DD",
    "breakfast": null,
    "lunch": null,
    "dinner": null,
    "activities": null,
    "people_met": null,
    "places_went": null,
    "mood": null,
    "raw_extract": "AI原始提取内容"
  }
}

例子：
- “我中午没吃啊”应进入 daily_life_record.lunch = "未进食"，raw_extract 写明老人提到中午没吃。
- “我以前在纺织厂上班”应进入 elder_basic_info.career，同时进入 memory_events。
- “我女儿小丽今天来看我了”应进入 family_members，也进入 daily_life_record.people_met。
- “那时候骑自行车上班有点冷”应进入 memory_events。
''';
