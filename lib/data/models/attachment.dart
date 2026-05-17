import 'dart:convert';

class AttachmentModel {
  AttachmentModel(
      {required this.id,
      required this.messageId,
      this.type,
      this.filePath,
      this.mime,
      this.size,
      this.metadata});

  final String id;
  final String messageId;
  final String? type;
  final String? filePath;
  final String? mime;
  final int? size;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toMap() => {
        'id': id,
        'message_id': messageId,
        'type': type,
        'file_path': filePath,
        'mime': mime,
        'size': size,
        'metadata': metadata == null ? null : _encode(metadata!),
      };

  static AttachmentModel fromMap(Map<String, dynamic> m) => AttachmentModel(
        id: m['id'] as String,
        messageId: m['message_id'] as String,
        type: m['type'] as String?,
        filePath: m['file_path'] as String?,
        mime: m['mime'] as String?,
        size: m['size'] as int?,
        metadata:
            m['metadata'] == null ? null : _decode(m['metadata'] as String),
      );

  static String _encode(Object o) => const JsonEncoder().convert(o);
  static Map<String, dynamic> _decode(String s) =>
      Map<String, dynamic>.from(const JsonDecoder().convert(s));
}
