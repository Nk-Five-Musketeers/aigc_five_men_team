import 'package:flutter/foundation.dart';

import '../data/models/chat_message.dart';
import '../data/repositories/chat_repository.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({ChatRepository? repository}) : _repository = repository ?? ChatRepository() {
    _messages.add(
      ChatMessage(
        id: 'welcome',
        content: '你好，我是 BlueCare。今天感觉怎么样？我们可以先从一件开心的小事聊起。',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  final ChatRepository _repository;
  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _isLoading = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  Future<void> sendMessage(String content) async {
    final text = content.trim();
    if (text.isEmpty) return;

    _messages.add(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        content: text,
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );
    _setLoading(true);

    try {
      final reply = await _repository.fetchReply(text);
      _messages.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}_assistant',
          content: reply,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      _messages.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}_assistant_error',
          content: '请求 AI 服务失败，请稍后重试。',
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
