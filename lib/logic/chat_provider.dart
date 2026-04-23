import 'package:flutter/foundation.dart';

import '../data/models/chat_message.dart';

class ChatProvider extends ChangeNotifier {
  final List<ChatMessage> _messages = <ChatMessage>[];

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    _messages.add(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        content: content,
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );

    _messages.add(
      ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}_assistant',
        content: '收到：$content',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    notifyListeners();
  }
}
