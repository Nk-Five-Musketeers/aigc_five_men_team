import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/constants.dart';
import '../../core/api_client.dart';
import '../models/chat_message.dart';
import '../models/extracted_relation_hint.dart';
import '../models/memory_extraction_payload.dart';
import '../models/photo_intent_plan.dart';

Stream<String> assistantTextDeltasFromSse(
  Stream<List<int>> byteStream,
) async* {
  await for (final line
      in byteStream.transform(utf8.decoder).transform(const LineSplitter())) {
    final trimmedLeft = line.trimLeft();
    if (!trimmedLeft.startsWith('data:')) continue;
    final dataText = trimmedLeft.substring(5).trimLeft();
    if (dataText.isEmpty) continue;
    if (dataText.trim() == '[DONE]') break;

    dynamic decoded;
    try {
      decoded = jsonDecode(dataText);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    final delta = _extractAssistantDelta(
      Map<String, dynamic>.from(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      ),
    );
    if (delta != null && delta.isNotEmpty) {
      yield delta;
    }
  }
}

String? _extractAssistantDelta(Map<String, dynamic> data) {
  final nested = data['data'];
  if (nested is Map) {
    final inner = Map<String, dynamic>.from(
      nested.map((k, v) => MapEntry(k.toString(), v)),
    );
    final t = _extractAssistantDelta(inner);
    if (t != null && t.isNotEmpty) return t;
  }

  final choices = data['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final choice = Map<String, dynamic>.from(
    first.map((k, v) => MapEntry(k.toString(), v)),
  );

  final delta = choice['delta'];
  if (delta is Map) {
    final d = Map<String, dynamic>.from(
      delta.map((k, v) => MapEntry(k.toString(), v)),
    );
    return _messageContentToString(d['content']);
  }

  final message = choice['message'];
  if (message is Map) {
    final m = Map<String, dynamic>.from(
      message.map((k, v) => MapEntry(k.toString(), v)),
    );
    return _messageContentToString(m['content']);
  }
  return _messageContentToString(choice['text']);
}

String? _messageContentToString(Object? content) {
  if (content == null) return null;
  if (content is String) return content;
  if (content is List) {
    final buf = StringBuffer();
    for (final part in content) {
      if (part is String) {
        buf.write(part);
      } else if (part is Map) {
        final m = Map<String, dynamic>.from(
          part.map((k, v) => MapEntry(k.toString(), v)),
        );
        final text = m['text'];
        if (text is String) buf.write(text);
      }
    }
    return buf.toString();
  }
  return null;
}

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
      "same_relation_key": "仅用户明确说「记错/不是某人」需按称谓对齐旧档案时填称谓，普通介绍留空"
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
6. same_relation_key（称谓定位）：**仅当**用户明确否认、纠正某一称谓下**原先所指的那个人**时填写该称谓（如「我女儿不是小红，是小明」「邻居记错了，不叫王芳」）。普通介绍「我女儿叫小丽」「我有个朋友叫阿强」**必须留空字符串**——同一称谓（如多位朋友、多个晚辈）可对应多条 people，留空可避免与旧档案误合并。若用户只是在补充另一位同称谓的亲友，不要填此字段。
7. 没有可登记人物时 people 为 []；其它数组无内容时为 []。
''';

/// 语音识别 → 送入主对话前：纠错、断句、去明显口误；不走记忆抽取长 system。
const _speechPolishSystemPrompt = '''
你是「语音识别结果整理」模块。用户消息中是一段由语音转写得到的中文文本，可能有同音错字、漏字、重复词、缺少标点。

请只做语言层面的整理，使内容读起来像老人自然说出的原话：
- 修正明显的错字与同音别字，补全极明显漏字；不要改写语气，不要书面化。
- 适当加逗号、句号分句；不要改成报告体或列表。
- 严格保留原意与人名、地名、数字、日期；**禁止**编造新的人名、事件或回答用户问题。
- 不要加开场白、不要解释过程、不要反问；不要输出「以下是…」等套话。

只输出整理后的正文一段，不要引号、不要 markdown。
''';

const _memoryAlbumPolishSystemPrompt = '''
你是「回忆图鉴正文润色」模块。你的任务不是重新创作图鉴，而是在给定事实和本地初稿基础上，把正文改得更自然、更连贯、更适合老人边看边听。

必须遵守：
1. 只基于输入中的 source_facts 和 local_album_draft 润色，禁止编造新人物、新地点、新时间、新经历、新亲属关系。
2. 保留所有 chapter_id 和 item_id；不要新增、删除、改名任何章节或卡片。
3. 不要改标题、照片 id、时间线、问题列表；只改 cover_text、opening_content、elder_profile_content、chapter_intro、item content、ending_content。
4. 如果某个 item 原 content 为空，输出也必须为空字符串，不能补故事。
5. 语言要像家属在温和讲述：自然、克制、连贯，适合朗读；避免字段味、报告味和模板味。
6. 每段控制在 2 到 4 句，句子不要过长；可以合并重复信息，让段落有起承转合。
7. 禁止出现「根据资料」「数据库」「字段」「信息不足」「未确认」「待补」「可以再补」「作为AI」等元叙述或占位话。
8. 只输出一个 JSON 对象，不要 markdown 代码块，不要解释。

输出 JSON 格式必须是：
{
  "cover_text": "",
  "opening_content": "",
  "elder_profile_content": "",
  "chapters": [
    {
      "chapter_id": "",
      "chapter_intro": "",
      "items": [
        {"item_id": "", "content": ""}
      ]
    }
  ],
  "ending_content": ""
}
''';

const _photoIntentSystemPrompt = '''
你是「老人相册选图」判定模块。根据老人一句话，结合【照片目录】判断要不要展示照片、要哪些、不要哪些。

请深度理解包含、排除、并列与否定，例如：
- 「输出风景照和头像」→ want_photos=true；include 同时含风景相关与 avatar 分类；exclude 为空。
- 「只要风景照，不要头像」→ want_photos=true；include 仅风景相关；exclude 含 avatar/头像。
- 「不要头像」且在看照片 → exclude 含头像；若未说要别的，include 可为空表示「除排除外其余相关」。
- 纯聊天、未要看图 → want_photos=false。

只输出一个 JSON 对象，不要 markdown，不要解释：
{
  "want_photos": true,
  "include_filters": [
    {
      "photo_ids": [],
      "categories": ["daily"],
      "keywords": ["风景"],
      "labels": ["风景照"]
    }
  ],
  "exclude_filters": [
    {
      "photo_ids": [],
      "categories": ["avatar"],
      "keywords": ["头像"],
      "labels": ["头像", "老人头像"]
    }
  ],
  "max_photos": 0,
  "reason_summary": "一句话说明"
}

字段说明：
- categories 仅用：avatar | family | memory | daily | other（与目录中英文分类一致）。
- photo_ids：仅当用户明确指向某 id 时填写，否则 []。
- keywords/labels：中文关键词，用于匹配说明、人物、地点、分类名。
- include_filters 为空且 want_photos=true：表示「在排除规则外，展示目录中所有仍相关的照片」。
- max_photos：用户明确张数则填数字，否则 0 由客户端处理。
''';

class ChatRepository {
  ChatRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<ChatMessage>> fetchHistory() async {
    return <ChatMessage>[];
  }

  /// 主对话由本地代理根据 [promptContext] 组合 `server/prompts`，不在此写入长 system。
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required Map<String, dynamic> promptContext,
  }) async {
    final messages = _compactHistory(history);

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: <String, dynamic>{
        'model': AppConstants.modelId,
        'messages': messages,
        'prompt_context': promptContext,
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

  /// Main chat reply as OpenAI-style SSE text deltas.
  Stream<String> streamMessage({
    required List<ChatMessage> history,
    required Map<String, dynamic> promptContext,
  }) async* {
    final messages = _compactHistory(history);

    final response = await _apiClient.dio.post<ResponseBody>(
      '/api/chat',
      data: <String, dynamic>{
        'model': AppConstants.modelId,
        'messages': messages,
        'prompt_context': promptContext,
        'temperature': 0.65,
        'top_p': 0.75,
        'max_tokens': 700,
        'reasoning_effort': 'minimal',
        'enable_thinking': false,
        'stream': true,
      },
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    final status = response.statusCode ?? 0;
    final body = response.data;
    if (status < 200 || status >= 300 || body == null) {
      final detail = body == null
          ? ''
          : await _decodeStreamError(body.stream.cast<List<int>>());
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: detail.isNotEmpty ? detail : '妯″瀷娴佸紡杩斿洖澶辫触 (HTTP $status)',
      );
    }

    yield* assistantTextDeltasFromSse(body.stream.cast<List<int>>());
  }

  Future<String> _decodeStreamError(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return '';
    final raw = utf8.decode(bytes, allowMalformed: true);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final detail = decoded['detail']?.toString();
        final error = decoded['error']?.toString();
        if (detail != null && detail.isNotEmpty) return detail;
        if (error != null && error.isNotEmpty) return error;
      }
    } catch (_) {}
    return raw.trim();
  }

  /// 本地 NLP 润色（`server/nlp_speech_polish.py`，无需 AppKey）。
  Future<String> polishSpeechTranscriptLocal(String rawTranscript) async {
    final raw = rawTranscript.trim();
    if (raw.isEmpty) return raw;

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/speech/polish',
      data: <String, dynamic>{'text': raw},
    );

    final data = response.data;
    final ok = data?['ok'] == true;
    final text = (data?['text'] as String?)?.trim() ?? '';
    if (!ok || text.isEmpty) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: '本地润色结果无效',
      );
    }
    return text;
  }

  /// 调用大模型整理语音识别文本；失败时由调用方回退为原文。
  ///
  /// 请求自带 [system] 消息，本地代理不会拼接陪伴场景的长 system（见 `local_chat_server.py`）。
  /// [knownNamesHint] 为档案中已有称谓/人名，仅用于对照纠错，勿编造。
  Future<String> polishSpeechTranscript(
    String rawTranscript, {
    String knownNamesHint = '',
  }) async {
    final raw = rawTranscript.trim();
    if (raw.isEmpty) return raw;

    var systemPrompt = _speechPolishSystemPrompt;
    final hint = knownNamesHint.trim();
    if (hint.isNotEmpty) {
      systemPrompt += '\n\n【档案中已有的人名/称谓（仅作同音错字对照，禁止编造新的人名）】\n$hint';
    }

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: <String, dynamic>{
        'model': AppConstants.modelId,
        'messages': <Map<String, String>>[
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '【语音识别结果】\n$raw'},
        ],
        'temperature': 0.12,
        'top_p': 0.45,
        'max_tokens': 2048,
        'reasoning_effort': 'minimal',
        'enable_thinking': false,
      },
    );

    final text = _extractAssistantText(response.data);
    if (text == null || text.trim().isEmpty) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: '润色结果为空',
      );
    }
    return _normalizePolishedSpeechOutput(text);
  }

  String _normalizePolishedSpeechOutput(String raw) {
    var s = _stripCodeFence(raw).trim();
    s = s.replaceFirst(
      RegExp(r'^(修正后|润色后|输出文本|输出结果|整理后)[:：]\s*', multiLine: true),
      '',
    );
    s = s.trim();
    if (s.length >= 2) {
      final first = s[0];
      final last = s[s.length - 1];
      const ldq = '\u201C';
      const rdq = '\u201D';
      if ((first == '"' || first == ldq) && (last == '"' || last == rdq)) {
        s = s.substring(1, s.length - 1).trim();
      }
    }
    if (s.length >= 2 && s[0] == '「' && s[s.length - 1] == '」') {
      s = s.substring(1, s.length - 1).trim();
    }
    return s.trim();
  }

  /// 用大模型润色本地生成的回忆图鉴正文。调用方负责把结果合并回本地图鉴；
  /// 这里仅返回可替换文本，避免模型改动结构、照片关联与时间线。
  Future<Map<String, dynamic>> polishMemoryAlbumTexts({
    required Map<String, dynamic> polishInput,
  }) async {
    final response = await _postStandaloneChat(
      chatTask: 'memory_album_polish',
      messages: <Map<String, String>>[
        {'role': 'system', 'content': _memoryAlbumPolishSystemPrompt},
        {
          'role': 'user',
          'content': const JsonEncoder.withIndent('  ').convert(polishInput),
        },
      ],
      temperature: 0.18,
      maxTokens: 4200,
    );

    final text = _requireAssistantText(response);
    final stripped = _stripCodeFence(text);
    final decoded = jsonDecode(stripped);
    if (decoded is! Map) {
      throw FormatException('回忆图鉴润色结果不是 JSON 对象', stripped);
    }
    return Map<String, dynamic>.from(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  /// 独立任务调用 /api/chat（自带 system，与主对话同模型同代理，参数与润色/抽取一致）。
  Future<Response<Map<String, dynamic>>> _postStandaloneChat({
    required List<Map<String, String>> messages,
    required String chatTask,
    double temperature = 0.15,
    int maxTokens = 1200,
  }) async {
    return _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: <String, dynamic>{
        'model': AppConstants.modelId,
        'messages': messages,
        'chat_task': chatTask,
        'temperature': temperature,
        'top_p': 0.5,
        'max_tokens': maxTokens,
        // 与主对话/润色一致：蓝心上游对 high+thinking 组合常直接返回 error
        'reasoning_effort': 'minimal',
        'enable_thinking': false,
      },
    );
  }

  /// 上游或代理返回 error 字段时抛出可读异常（避免误判为「结果为空」）。
  void _throwIfChatResponseError(
      Map<String, dynamic>? data, Response response) {
    if (data == null) return;
    final err = data['error'];
    if (err == null) return;
    final msg = _formatApiError(err);
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: msg.isEmpty ? '大模型接口返回 error' : msg,
    );
  }

  String _formatApiError(Object err) {
    if (err is String) return err.trim();
    if (err is Map) {
      final m = Map<String, dynamic>.from(
        err.map((k, v) => MapEntry(k.toString(), v)),
      );
      final message = (m['message'] as String?)?.trim();
      final detail = (m['detail'] as String?)?.trim();
      final code = m['code']?.toString();
      final type = (m['type'] as String?)?.trim();
      final parts = <String>[
        if (message != null && message.isNotEmpty) message,
        if (detail != null && detail.isNotEmpty) detail,
        if (code != null && code.isNotEmpty) 'code=$code',
        if (type != null && type.isNotEmpty) 'type=$type',
      ];
      if (parts.isNotEmpty) return parts.join(' | ');
      return m.values.map((v) => v.toString()).join(' ');
    }
    return err.toString();
  }

  /// 从独立任务响应中取出 assistant 文本；失败则抛 [DioException]。
  String _requireAssistantText(Response<Map<String, dynamic>> response) {
    final data = response.data;
    _throwIfChatResponseError(data, response);
    final text = _extractAssistantText(data);
    if (text != null && text.trim().isNotEmpty) return text.trim();
    final keys = data?.keys.map((e) => e.toString()).join(',') ?? '';
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: '大模型返回无可用文本（keys: $keys）',
    );
  }

  /// 兼容多种 OpenAI 风格返回（字符串 content、分片列表、reasoning 字段、delta 等）。
  String? _extractAssistantText(Map<String, dynamic>? data) {
    if (data == null) return null;
    // 含 error 且无 choices 时不再向下解析
    if (data.containsKey('error') && data['choices'] == null) {
      final nested = data['data'];
      if (nested is! Map || !nested.containsKey('choices')) return null;
    }
    // 兼容 vivo 平台把 OpenAI 风格结果包在 data 字段里：
    // { "code": 0, "msg": "...", "data": { "choices": [...] } }
    final nested = data['data'];
    if (nested is Map) {
      final inner = Map<String, dynamic>.from(
        nested.map((k, v) => MapEntry(k.toString(), v)),
      );
      final t = _extractAssistantText(inner);
      if (t != null && t.trim().isNotEmpty) return t;
    }
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
          final m = Map<String, dynamic>.from(
            part.map((k, v) => MapEntry(k.toString(), v)),
          );
          final text = m['text'];
          if (text is String && text.isNotEmpty) buf.write(text);
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
        .where((item) =>
            item.kind == ChatMessageKind.text ||
            item.kind == ChatMessageKind.error)
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
      final desc =
          (_pickStr(m, const ['description', '描述', '详细描述']) ?? '').trim();
      if (title.length < 2 && desc.length < 4) continue;
      final et = _pickStr(m, const ['event_time', 'eventTime', '事件发生时间']) ?? '';
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
      final parts = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
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

  List<ExtractedRelationHint> _peopleHintsFromDecoded(
      Map<String, dynamic> root) {
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
          sameRelationKey:
              (srk != null && srk.trim().isNotEmpty) ? srk.trim() : null,
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

  /// 调用蓝心 / DeepSeek 判定本次要展示的照片条件（含排除）。
  Future<PhotoIntentPlan> analyzePhotoDisplayIntent({
    required String userMessage,
    required String photoCatalog,
    bool isRejectionContinuation = false,
    String? previousUserQuery,
    List<String> recentlyShownPhotoIds = const [],
  }) async {
    final buf = StringBuffer()
      ..writeln('【照片目录（每行一张，仅可引用下列 id）】')
      ..writeln(photoCatalog)
      ..writeln();

    if (isRejectionContinuation) {
      buf
        ..writeln('【场景】老人表示上一张不对，需要换一批。')
        ..writeln('【上一轮检索原话】${previousUserQuery ?? ''}')
        ..writeln('【本轮已展示过的 photo_id】${recentlyShownPhotoIds.join('、')}')
        ..writeln('【老人本轮原话】$userMessage');
    } else {
      buf.writeln('【老人原话】$userMessage');
    }

    final response = await _postStandaloneChat(
      chatTask: 'photo_intent',
      messages: <Map<String, String>>[
        {'role': 'system', 'content': _photoIntentSystemPrompt},
        {'role': 'user', 'content': buf.toString()},
      ],
      temperature: 0.12,
      maxTokens: 1200,
    );

    final text = _requireAssistantText(response);
    return _parsePhotoIntentPlan(text);
  }

  PhotoIntentPlan _parsePhotoIntentPlan(String raw) {
    final stripped = _stripCodeFence(raw);
    if (stripped.isEmpty) return PhotoIntentPlan.empty;
    try {
      final decoded = jsonDecode(stripped);
      if (decoded is! Map) return PhotoIntentPlan.empty;
      final root = Map<String, dynamic>.from(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
      final want = root['want_photos'] == true;
      return PhotoIntentPlan(
        wantPhotos: want,
        includeFilters: _parsePhotoFilters(root['include_filters']),
        excludeFilters: _parsePhotoFilters(root['exclude_filters']),
        maxPhotos: (root['max_photos'] as num?)?.toInt() ?? 0,
        reasonSummary: (root['reason_summary'] as String?)?.trim() ?? '',
      );
    } catch (_) {
      return PhotoIntentPlan.empty;
    }
  }

  List<PhotoIntentFilter> _parsePhotoFilters(dynamic raw) {
    if (raw is! List) return const [];
    final out = <PhotoIntentFilter>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(
        item.map((k, v) => MapEntry(k.toString(), v)),
      );
      out.add(
        PhotoIntentFilter(
          photoIds: _stringList(m['photo_ids']),
          categories: _stringList(m['categories']),
          keywords: _stringList(m['keywords']),
          labels: _stringList(m['labels']),
        ),
      );
    }
    return out;
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
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
