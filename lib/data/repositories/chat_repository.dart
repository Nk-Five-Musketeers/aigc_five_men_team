import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/constants.dart';
import '../../core/api_client.dart';
import '../models/chat_message.dart';
import '../models/extracted_relation_hint.dart';
import '../models/memory_extraction_payload.dart';

const _fullMemoryExtractSystemPrompt = '''
你是结构化信息抽取模块。用户消息中只会提供**老人本人的发言文本**（不含陪伴助手/拾忆的回复）。请仅根据这些发言、已有周围人摘要、已有老人档案摘要抽取可写入本地数据库的结构化信息；**禁止**把助手说过的人名、经历、电话等当作事实写入 JSON。
请只输出**一个** JSON 对象，不要 markdown 代码块，不要任何解释或前后缀文字。

顶层键必须全部出现，结构如下（示例值为类型说明，请替换为真实抽取结果；无信息用空字符串 ""、空数组 [] 或 daily_life 用 null）：
{
  "people": [
    {
      "name": "2-6字常见中文名",
      "relation": "女儿/儿子/邻居/朋友等，无则空字符串",
      "phone": "11位手机号或空字符串",
      "note": "一句补充或空字符串",
      "same_relation_key": "仅姓名更正时填档案称谓，否则空字符串"
    }
  ],
  "elder_profile": {
    "name": "老人自称或确认的称呼/姓名，无则空",
    "birth_year": "如 1945年3月 或空",
    "hometown": "",
    "career": "",
    "hobbies": "",
    "food_preference": "",
    "personality": "",
    "taboo": "",
    "dialect": "",
    "avatar_path": ""
  },
  "family_members": [
    {
      "name": "",
      "relation": "大儿子/女儿等",
      "photo_path": "",
      "birthday": "",
      "location": "",
      "contact_freq": "",
      "notes": "",
      "is_active": true
    }
  ],
  "memory_events": [
    {
      "event_time": "如 1968年夏天 或空",
      "title": "简短标题",
      "description": "细节或空",
      "location": "",
      "people_involved": "",
      "emotion": "",
      "photo_paths": "",
      "video_path": "",
      "importance": 3,
      "source": "AI提取",
      "verified": false
    }
  ],
  "daily_life": null
}

daily_life 若非 null，则为对象：
{
  "date": "YYYY-MM-DD",
  "breakfast": "",
  "lunch": "",
  "dinner": "",
  "activities": "",
  "people_met": "",
  "places_went": "",
  "mood": ""
}

规则（重要）：
0. 输入片段全部为「用户侧」发言：凡助手侧可能出现的虚构称呼、人物、号码一律不得写入；仅老人亲口或明确确认的信息可落库。
1. people：与旧版一致，登记对话中出现的**他人**（亲友、邻居等），不要登记助手/拾忆/机器人；不要把我方老人本人当作 people 里的一条。
2. elder_profile：仅填老人**本人**在对话中**明确说出**的履历、籍贯、职业、爱好、饮食偏好、性格、忌讳、方言等；助手复述若未经老人确认则不要写入。字段无依据则保持空字符串。
3. family_members：登记血缘/姻亲或对话中明确为「家里人」的成员，尽量补全结构化字段；is_active 表示是否在世（默认 true）。
4. memory_events：老人回忆的**往事片段**（通常不是「今天吃了啥」）；每条一事，title 尽量短；无往事则 []。
5. daily_life：仅当对话明确涉及**某一天**的日常（含「今天」「昨天」及饮食活动心情）时输出对象且 date 必须为 YYYY-MM-DD；无法确定日期则 daily_life 必须为 null。
6. same_relation_key 规则同 people 旧版说明。
7. 没有可登记人物时 people 为 []；其它数组无内容时为 []。
''';

class ChatRepository {
  ChatRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<ChatMessage>> fetchHistory() async {
    return <ChatMessage>[];
  }

  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String systemPrompt,
  }) async {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ..._compactHistory(history),
    ];

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: <String, dynamic>{
        'model': AppConstants.modelId,
        'messages': messages,
        'temperature': 0.65,
        'top_p': 0.75,
        'max_tokens': 700,
        'reasoning_effort': 'minimal',
        'enable_thinking': false,
      },
    );

    final data = response.data;
    final text = _extractAssistantText(data);
    if (text != null && text.isNotEmpty) {
      return text;
    }

    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: '模型返回为空或格式无法识别',
    );
  }

  /// 兼容多种 OpenAI 风格返回（字符串 content、分片列表、reasoning 字段、delta 等）。
  String? _extractAssistantText(Map<String, dynamic>? data) {
    if (data == null) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final choice = Map<String, dynamic>.from(
      first.map((k, v) => MapEntry(k.toString(), v)),
    );

    final message = choice['message'];
    if (message is Map) {
      final m = Map<String, dynamic>.from(
        message.map((k, v) => MapEntry(k.toString(), v)),
      );
      final fromContent = _stringFromMessageContent(m['content']);
      if (fromContent != null) return fromContent;
      final reasoning = m['reasoning_content'];
      if (reasoning is String && reasoning.trim().isNotEmpty) {
        return reasoning.trim();
      }
    }

    final delta = choice['delta'];
    if (delta is Map) {
      final d = Map<String, dynamic>.from(
        delta.map((k, v) => MapEntry(k.toString(), v)),
      );
      final fromDelta = _stringFromMessageContent(d['content']);
      if (fromDelta != null) return fromDelta;
    }

    final legacy = choice['text'];
    if (legacy is String && legacy.trim().isNotEmpty) {
      return legacy.trim();
    }
    return null;
  }

  String? _stringFromMessageContent(Object? content) {
    if (content == null) return null;
    if (content is String) {
      final t = content.trim();
      return t.isEmpty ? null : t;
    }
    if (content is List) {
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          final text = part['text'];
          if (text is String) buf.write(text);
        } else if (part is String) {
          buf.write(part);
        }
      }
      final t = buf.toString().trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  List<Map<String, String>> _compactHistory(List<ChatMessage> history) {
    final normalMessages = history
        .where((item) => item.kind == ChatMessageKind.text || item.kind == ChatMessageKind.error)
        .toList();
    final recent = normalMessages.length > 12
        ? normalMessages.sublist(normalMessages.length - 12)
        : normalMessages;

    return recent
        .map(
          (item) => <String, String>{
            'role': item.isUser ? 'user' : 'assistant',
            'content': item.content,
          },
        )
        .toList();
  }

  /// 调用大模型从近期对话中抽取人物关系（内部走 [extractFullMemoryFromChat]，仅返回 people）。
  Future<List<ExtractedRelationHint>> extractRelationsFromChat({
    required List<Map<String, String>> transcriptMessages,
    required String existingNearbySummary,
    String existingUserSummary = '（尚无老人档案摘要）',
  }) async {
    final payload = await extractFullMemoryFromChat(
      transcriptMessages: transcriptMessages,
      existingNearbySummary: existingNearbySummary,
      existingUserSummary: existingUserSummary,
    );
    return payload.people;
  }

  /// 一次请求抽取：周围人 people、老人本人 elder_profile、家庭成员、记忆事件、每日生活。
  Future<MemoryExtractionPayload> extractFullMemoryFromChat({
    required List<Map<String, String>> transcriptMessages,
    required String existingNearbySummary,
    required String existingUserSummary,
  }) async {
    final buf = StringBuffer()
      ..writeln('【已有老人档案摘要（仅作对照，勿编造）】')
      ..writeln(existingUserSummary.trim())
      ..writeln()
      ..writeln('【已有周围人档案（对照冲突）】')
      ..writeln(existingNearbySummary.trim())
      ..writeln()
      ..writeln(
        '【老人近期发言（仅含用户侧文本，不含助手回复；请只根据下列发言与上文摘要抽取，勿引用助手话术）】',
      );
    for (final m in transcriptMessages) {
      buf.writeln('- ${m['content'] ?? ''}');
    }

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: <String, dynamic>{
        'model': AppConstants.modelId,
        'messages': <Map<String, String>>[
          {'role': 'system', 'content': _fullMemoryExtractSystemPrompt},
          {'role': 'user', 'content': buf.toString()},
        ],
        'temperature': 0.08,
        'top_p': 0.45,
        'max_tokens': 1800,
        'reasoning_effort': 'minimal',
        'enable_thinking': false,
      },
    );

    final text = _extractAssistantText(response.data);
    if (text == null || text.isEmpty) {
      return MemoryExtractionPayload.empty();
    }
    return _parseFullMemoryPayload(text);
  }

  MemoryExtractionPayload _parseFullMemoryPayload(String raw) {
    final stripped = _stripCodeFence(raw);
    if (stripped.isEmpty) return MemoryExtractionPayload.empty();
    try {
      final decoded = jsonDecode(stripped);
      if (decoded is Map) {
        final root = Map<String, dynamic>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
        return MemoryExtractionPayload(
          people: _peopleHintsFromDecoded(root),
          elderProfilePatch: _parseElderProfilePatch(root['elder_profile']),
          familyMemberRows: _parseFamilyMemberRows(root['family_members']),
          memoryEventRows: _parseMemoryEventRows(root['memory_events']),
          dailyLifePatch: _parseDailyLifePatch(root['daily_life']),
          rawAssistantJson: stripped,
        );
      }
      if (decoded is List<dynamic>) {
        return MemoryExtractionPayload(
          people: _peopleHintsFromPeopleList(decoded),
          rawAssistantJson: stripped,
        );
      }
      return MemoryExtractionPayload.empty();
    } catch (_) {
      return MemoryExtractionPayload(
        people: _parsePeopleJson(stripped),
        rawAssistantJson: stripped,
      );
    }
  }

  static const _elderProfileKeys = <String>[
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

  Map<String, String> _parseElderProfilePatch(dynamic v) {
    if (v is! Map) return {};
    final m = Map<String, dynamic>.from(
      v.map((k, val) => MapEntry(k.toString(), val)),
    );
    final out = <String, String>{};
    for (final key in _elderProfileKeys) {
      final s = _pickStr(m, [key]) ?? '';
      if (s.isNotEmpty) {
        out[key] = s;
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _parseFamilyMemberRows(dynamic v) {
    if (v is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in v) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(
        item.map((k, val) => MapEntry(k.toString(), val)),
      );
      final name = _pickStr(m, const ['name', '姓名']) ?? '';
      if (name.trim().length < 2) continue;
      final rel = _pickStr(m, const ['relation', '关系']) ?? '';
      final row = <String, dynamic>{
        'name': name.trim(),
        'relation': rel.trim(),
        'photo_path': _pickStr(m, const ['photo_path', 'photoPath']) ?? '',
        'birthday': _pickStr(m, const ['birthday', '生日']) ?? '',
        'location': _pickStr(m, const ['location', '居住地']) ?? '',
        'contact_freq':
            _pickStr(m, const ['contact_freq', 'contactFreq', '联系频率']) ?? '',
        'notes': _pickStr(m, const ['notes', 'note', '备注']) ?? '',
        'is_active': _parseBool01(m['is_active'], defaultVal: true),
      };
      out.add(row);
    }
    return out;
  }

  List<Map<String, dynamic>> _parseMemoryEventRows(dynamic v) {
    if (v is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in v) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(
        item.map((k, val) => MapEntry(k.toString(), val)),
      );
      final title = (_pickStr(m, const ['title', '标题']) ?? '').trim();
      final desc = (_pickStr(m, const ['description', '描述', '详细描述']) ?? '').trim();
      if (title.length < 2 && desc.length < 4) continue;
      final et =
          _pickStr(m, const ['event_time', 'eventTime', '事件发生时间']) ?? '';
      final importance = _clampInt(m['importance'], 1, 5, defaultVal: 3);
      final photoPathsRaw = m['photo_paths'] ?? m['photoPaths'];
      final photoPaths = _photoPathsToText(photoPathsRaw);
      final resolvedTitle = title.isNotEmpty
          ? title
          : (desc.isNotEmpty
              ? desc.substring(0, desc.length > 48 ? 48 : desc.length)
              : '记忆片段');
      out.add(<String, dynamic>{
        'event_time': et,
        'title': resolvedTitle,
        'description': desc,
        'location': _pickStr(m, const ['location', '地点']) ?? '',
        'people_involved':
            _pickStr(m, const ['people_involved', 'peopleInvolved', '涉及人物']) ??
                '',
        'emotion': _pickStr(m, const ['emotion', '情感']) ?? '',
        'photo_paths': photoPaths,
        'video_path': _pickStr(m, const ['video_path', 'videoPath']) ?? '',
        'importance': importance,
        'source': _pickStr(m, const ['source', '来源']) ?? 'AI提取',
        'verified': _parseBool01(m['verified'], defaultVal: false),
      });
    }
    return out;
  }

  String _photoPathsToText(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is List) {
      final parts = raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      return jsonEncode(parts);
    }
    return raw.toString().trim();
  }

  Map<String, dynamic>? _parseDailyLifePatch(dynamic v) {
    if (v == null || v == false) return null;
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(
      v.map((k, val) => MapEntry(k.toString(), val)),
    );
    final keys = <String>[
      'date',
      'breakfast',
      'lunch',
      'dinner',
      'activities',
      'people_met',
      'places_went',
      'mood',
    ];
    var any = false;
    for (final k in keys) {
      final s = _pickStr(m, [k]) ?? '';
      if (k == 'date' && s.isNotEmpty) any = true;
      if (k != 'date' && s.isNotEmpty) any = true;
    }
    if (!any) return null;
    final patch = <String, dynamic>{};
    for (final k in keys) {
      patch[k] = _pickStr(m, [k]) ?? '';
    }
    return patch;
  }

  int _clampInt(Object? v, int min, int max, {required int defaultVal}) {
    final n = v is int
        ? v
        : v is num
            ? v.toInt()
            : int.tryParse(v?.toString() ?? '');
    if (n == null) return defaultVal;
    if (n < min) return min;
    if (n > max) return max;
    return n;
  }

  int _parseBool01(Object? v, {required bool defaultVal}) {
    if (v == null) return defaultVal ? 1 : 0;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v != 0 ? 1 : 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '是' || s == '1' || s == 'yes') return 1;
    if (s == 'false' || s == '否' || s == '0' || s == 'no') return 0;
    return defaultVal ? 1 : 0;
  }

  List<ExtractedRelationHint> _peopleHintsFromDecoded(Map<String, dynamic> root) {
    final list = root['people'] as List<dynamic>? ??
        root['data'] as List<dynamic>? ??
        root['人物列表'] as List<dynamic>?;
    if (list == null) return [];
    return _peopleHintsFromPeopleList(list);
  }

  List<ExtractedRelationHint> _peopleHintsFromPeopleList(List<dynamic> list) {
    final out = <ExtractedRelationHint>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(
        item.map((k, v) => MapEntry(k.toString(), v)),
      );
      final name = _pickStr(m, const ['name', '姓名', '人物', '人物姓名']) ?? '';
      if (name.length < 2) continue;

      final srk = _pickStr(m, const [
        'same_relation_key',
        'sameRelationKey',
        '称谓定位',
        '对应称谓',
      ]);
      out.add(
        ExtractedRelationHint(
          name: name,
          relation: _pickStr(m, const ['relation', '关系', '称谓']),
          phone: _pickStr(m, const ['phone', '电话', '手机', 'mobile']),
          note: _pickStr(m, const ['note', '备注', '说明']),
          sameRelationKey: (srk != null && srk.trim().isNotEmpty)
              ? srk.trim()
              : null,
        ),
      );
    }
    return out;
  }

  /// 兼容仅返回 people 数组的旧模型输出。
  List<ExtractedRelationHint> _parsePeopleJson(String stripped) {
    try {
      final decoded = jsonDecode(stripped);
      if (decoded is Map<String, dynamic>) {
        return _peopleHintsFromDecoded(
          Map<String, dynamic>.from(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          ),
        );
      }
      if (decoded is List<dynamic>) {
        return _peopleHintsFromPeopleList(decoded);
      }
    } catch (_) {}
    return [];
  }

  String _stripCodeFence(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final nl = s.indexOf('\n');
      if (nl != -1) {
        s = s.substring(nl + 1);
      }
      final end = s.lastIndexOf('```');
      if (end != -1) {
        s = s.substring(0, end);
      }
    }
    s = s.trim();
    final i0 = s.indexOf('{');
    final i1 = s.lastIndexOf('}');
    if (i0 != -1 && i1 != -1 && i1 > i0) {
      s = s.substring(i0, i1 + 1);
    }
    return s.trim();
  }

  static String? _pickStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final t = v.toString().trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }
}
