import 'package:dio/dio.dart';

import '../../config/constants.dart';
import '../../core/api_client.dart';
import '../models/chat_message.dart';

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
    final choices = data?['choices'];
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

    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: '模型返回为空',
    );
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
}
