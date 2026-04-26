enum ChatMessageKind {
  text,
  memoryPrompt,
  cognitivePrompt,
  error,
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.kind = ChatMessageKind.text,
    this.title,
    this.options = const <String>[],
    this.cueLabel,
  });

  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final ChatMessageKind kind;
  final String? title;
  final List<String> options;
  final String? cueLabel;
}
