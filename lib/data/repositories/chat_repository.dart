import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../config/constants.dart';

class ChatRepository {
  ChatRepository() : _apiClient = ApiClient();

  final ApiClient _apiClient;
  final Uuid _uuid = const Uuid();

  Future<String> fetchReply(String content) async {
    final String requestId = _uuid.v4();

    try {
      print('Sending request with ID: $requestId');
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/chat/completions',
        queryParameters: {'request_id': requestId},
        data: {
          'model': AppConstants.modelId,
          'messages': [
            {
              'role': 'system',
              'content': AppConstants.systemPrompt,
            },
            {
              'role': 'user',
              'content': content,
            },
          ],
          'temperature': 0.8,
          'max_tokens': 1024,
          'stream': false,
          'reasoning_effort': 'low',
        },
      );

      print('Response status: ${response.statusCode}');
      final data = response.data;
      if (data == null) {
        throw Exception('API 返回为空');
      }

      print('Response data: $data');
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw Exception('API 未返回 choices');
      }

      final firstChoice = choices.first as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>?;
      final contentText = message?['content']?.toString();
      if (contentText == null || contentText.isEmpty) {
        throw Exception('API 返回的回复为空');
      }

      return contentText;
    } on DioException catch (error) {
      print('DioException: ${error.message}');
      print('Response: ${error.response}');
      final status = error.response?.statusCode;
      final body = error.response?.data;
      throw Exception('API 请求失败（status: $status, body: $body）');
    } catch (error) {
      print('Other error: $error');
      throw Exception('API 请求异常：$error');
    }
  }
}
