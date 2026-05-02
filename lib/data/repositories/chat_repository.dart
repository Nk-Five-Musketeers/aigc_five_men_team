import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/constants.dart';
import '../../core/api_client.dart';
import '../models/chat_message.dart';
import '../models/extracted_relation_hint.dart';

const _relationExtractSystemPrompt = '''
你是结构化信息抽取模块。根据「老人与助手的聊天记录」和「已有周围人档案摘要」，提取其中出现的**具体人物**及与老人的关系、电话、备注。
请只输出**一个** JSON 对象，不要 markdown 代码块，不要任何解释、前后缀文字。格式严格为：
{"people":[{"name":"人名(2-6字常见中文名)","relation":"如女儿/儿子/邻居/朋友，无则空字符串","phone":"11位手机号或空字符串","note":"一句补充，无则空字符串"}]}
规则：
- 只提取真实人物，不要「我」与老人自己同义；不要虚拟助手/拾忆/机器人。
- 没有可登记人物时输出 {"people":[]}
- 同一人只保留一条，信息合并。
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

  /// 调用大模型从近期对话中抽取人物关系，写入库前由上层合并/冲突检测。
  Future<List<ExtractedRelationHint>> extractRelationsFromChat({
    required List<Map<String, String>> transcriptMessages,
    required String existingNearbySummary,
  }) async {
    final buf = StringBuffer()
      ..writeln('【已有周围人档案（对照冲突）】')
      ..writeln(existingNearbySummary.trim())
      ..writeln()
      ..writeln('【最近对话节选】');
    for (final m in transcriptMessages) {
      buf.writeln('${m['role']}: ${m['content']}');
    }

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: <String, dynamic>{
        'model': AppConstants.modelId,
        'messages': <Map<String, String>>[
          {'role': 'system', 'content': _relationExtractSystemPrompt},
          {'role': 'user', 'content': buf.toString()},
        ],
        'temperature': 0.08,
        'top_p': 0.45,
        'max_tokens': 900,
        'reasoning_effort': 'minimal',
        'enable_thinking': false,
      },
    );

    final text = _extractAssistantText(response.data);
    if (text == null || text.isEmpty) return [];
    return _parsePeopleJson(text);
  }

  List<ExtractedRelationHint> _parsePeopleJson(String raw) {
    final stripped = _stripCodeFence(raw);
    if (stripped.isEmpty) return [];
    try {
      final decoded = jsonDecode(stripped);
      List<dynamic>? list;
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        list = map['people'] as List<dynamic>? ??
            map['data'] as List<dynamic>? ??
            map['人物列表'] as List<dynamic>?;
      } else if (decoded is List<dynamic>) {
        list = decoded;
      }
      if (list == null) return [];

      final out = <ExtractedRelationHint>[];
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        final name = _pickStr(m, const ['name', '姓名', '人物', '人物姓名']) ?? '';
        if (name.length < 2) continue;

        out.add(
          ExtractedRelationHint(
            name: name,
            relation: _pickStr(m, const ['relation', '关系', '称谓']),
            phone: _pickStr(m, const ['phone', '电话', '手机', 'mobile']),
            note: _pickStr(m, const ['note', '备注', '说明']),
          ),
        );
      }
      return out;
    } catch (_) {
      return [];
    }
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
