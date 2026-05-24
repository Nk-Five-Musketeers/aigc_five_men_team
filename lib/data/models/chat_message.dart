enum ChatMessageKind {
  text,
  memoryPrompt,
  cognitivePrompt,
  error,
  /// 本地 [profile_photos] 档案中的图片回复。
  photo,
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
    this.imagePath,
    this.profilePhotoId,
  });

  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final ChatMessageKind kind;
  final String? title;
  final List<String> options;
  final String? cueLabel;
  /// 本地文件路径或 Web data URL。
  final String? imagePath;
  final String? profilePhotoId;
}
