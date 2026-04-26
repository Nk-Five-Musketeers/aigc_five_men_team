import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../data/models/chat_message.dart';
import '../data/repositories/chat_repository.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({ChatRepository? repository}) : _repository = repository ?? ChatRepository() {
    _messages.add(
      ChatMessage(
        id: 'welcome',
        content: '今天想聊什么？我在这里陪着您，慢慢说就好。',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  final ChatRepository _repository;
  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _isLoading = false;

  bool _isSending = false;
  int _userTurnCount = 0;

  bool get isSending => _isSending;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  Future<void> sendMessage(String content) async {
    final text = content.trim();
    if (text.isEmpty || _isSending) return;

    _userTurnCount += 1;
    _messages.add(_textMessage(content: text, isUser: true));
    _isSending = true;
    notifyListeners();

    try {
      final reply = await _repository.sendMessage(
        history: _messages,
        systemPrompt: _buildSystemPrompt(),
      );
      _messages.add(_textMessage(content: reply, isUser: false));
      _insertSupportCardIfNeeded(text);
    } catch (error) {
      _messages.add(
        ChatMessage(
          id: _newId('error'),
          content: _buildErrorMessage(error),
          isUser: false,
          timestamp: DateTime.now(),
          kind: ChatMessageKind.error,
        ),
      );
      _insertLocalMemoryPrompt(text);
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void sendOption(String text) {
    sendMessage(text);
  }

  ChatMessage _textMessage({
    required String content,
    required bool isUser,
  }) {
    return ChatMessage(
      id: _newId(isUser ? 'user' : 'assistant'),
      content: content,
      isUser: isUser,
      timestamp: DateTime.now(),
    );
  }

  void _insertSupportCardIfNeeded(String latestUserText) {
    if (_userTurnCount % 3 == 0) {
      _messages.add(
        ChatMessage(
          id: _newId('cognitive'),
          title: '小小回忆练习',
          content: '我这里有一张老家院子的照片。您还记得院子里常放着什么吗？',
          isUser: false,
          timestamp: DateTime.now(),
          kind: ChatMessageKind.cognitivePrompt,
          cueLabel: '老家小院',
          options: const <String>['水缸', '自行车', '再想想'],
        ),
      );
      return;
    }

    if (_mentionsMemory(latestUserText) || _userTurnCount % 2 == 0) {
      _messages.add(
        ChatMessage(
          id: _newId('memory'),
          title: '记忆锚点',
          content: '记得您说过以前常骑自行车去上班。那时候早晨路上会不会有点冷？',
          isUser: false,
          timestamp: DateTime.now(),
          kind: ChatMessageKind.memoryPrompt,
          cueLabel: '1986 · 自行车',
          options: const <String>['有点冷', '不太冷', '记不清了'],
        ),
      );
    }
  }

  void _insertLocalMemoryPrompt(String latestUserText) {
    if (!_mentionsMemory(latestUserText)) return;
    _messages.add(
      ChatMessage(
        id: _newId('local-memory'),
        title: '我们慢慢回忆',
        content: '您刚刚提到了以前的事。要不要从“老家小院的午后”开始说起？',
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.memoryPrompt,
        cueLabel: '老家小院',
        options: const <String>['好呀', '想看照片', '再等等'],
      ),
    );
  }

  bool _mentionsMemory(String text) {
    return text.contains('以前') ||
        text.contains('照片') ||
        text.contains('女儿') ||
        text.contains('上班') ||
        text.contains('老家') ||
        text.contains('自行车') ||
        text.contains('记得');
  }

  String _buildSystemPrompt() {
    return '''
你是“暖忆陪伴”，一款面向阿尔兹海默症早期老人、MCI阶段老人、健忘老人和空巢老人的陪伴关怀助手。

你的目标：
1. 像耐心、温暖、可信的老朋友一样陪老人说话。
2. 老人随口提到事情时，优先联系“已有记忆资料”，自然追问，帮助扩充记忆数据库。
3. 在话题自然停顿时，用提问型方式开启和老人记忆相关的新话题。
4. 适时加入轻量认知干预，例如识别人、日常物品、地点、天气、旧职业、亲友关系，但语气必须像聊天，不能像考试。
5. 不做医疗诊断，不使用“病情、治疗、评估结果”等医学结论。

已有记忆资料：
- 用户称呼：王阿姨。
- 王阿姨年轻时在纺织厂工作，常骑自行车去上班。
- 1986年春天，她常提到“春天里的自行车”。
- 她有一个女儿，看到旧照片时常会笑着讲女儿小时候的事。
- 老家有一个小院，午后常有阳光，也常放着水缸和自行车。
- 最近记录：中午吃了面条，胃口不错；午休情况正常。

回复规则：
- 每次回复控制在2到4句话。
- 先回应情绪，再轻轻追问。
- 追问一次即可，不要连珠炮。
- 如果老人记不清，要安慰：“没关系，我们慢慢想”。
- 语言使用自然中文，不要机械，不要提“数据库、认知干预、模型”等词。
''';
  }

  String _buildErrorMessage(Object error) {
    if (error is DioException) {
      return '我这会儿有点连不上服务，但我还在。我们可以先慢慢聊，您刚刚说的我记下了。';
    }
    return '我刚刚没有听清楚，您可以再慢慢说一遍。';
  }

  String _newId(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }
}
