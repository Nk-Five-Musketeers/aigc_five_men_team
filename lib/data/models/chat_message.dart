enum ChatMessageKind {
  text,
  memoryPrompt,
  cognitivePrompt,
  error,
  /// 本地 [profile_photos] 档案中的图片回复。
  photo,
  /// 用户通过「+」上传的图片或视频。
  attachment,
}

enum ChatAttachmentMediaType {
  image,
  video,
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
    this.attachmentMediaType,
    this.videoPath,
    this.attachmentId,
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
  /// 用户附件类型（图片 / 视频）。
  final ChatAttachmentMediaType? attachmentMediaType;
  /// 视频本地路径（图片仍用 [imagePath]）。
  final String? videoPath;
  final String? attachmentId;

  bool get hasMediaAttachment =>
      kind == ChatMessageKind.attachment &&
      ((attachmentMediaType == ChatAttachmentMediaType.image &&
              imagePath != null &&
              imagePath!.isNotEmpty) ||
          (attachmentMediaType == ChatAttachmentMediaType.video &&
              videoPath != null &&
              videoPath!.isNotEmpty));
}
