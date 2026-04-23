import 'package:flutter/foundation.dart';

import '../data/models/chat_message.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider() {
    _messages.add(
      ChatMessage(
        id: 'welcome',
        content: '你好，我是 BlueCare。今天感觉怎么样？我们可以先从一件开心的小事聊起。',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  final List<ChatMessage> _messages = <ChatMessage>[];

  List<ChatMessage> get messages => List.unmodifiable(_messages);

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
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 520));

    _messages.add(
      ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}_assistant',
        content: _buildReply(text),
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  String _buildReply(String text) {
    if (text.contains('喝水') || text.contains('口渴')) {
      return '收到，我记下来了。先喝半杯温水，等会我们再聊聊今天的状态。';
    }
    if (text.contains('记忆') || text.contains('以前')) {
      return '我们一起回忆一下吧。你可以说说印象最深的一次家庭旅行，我来帮你整理成小故事。';
    }
    if (text.contains('担心') || text.contains('焦虑')) {
      return '谢谢你愿意告诉我。先深呼吸三次，我会陪着你慢慢聊，不着急。';
    }
    return '我听到了：“$text”。如果你愿意，我可以继续追问几个轻松的问题，帮你把想法整理清楚。';
  }
}
