import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../data/local_db/local_database.dart';
import 'profile_photo_storage.dart';

enum ChatAttachmentType { image, video }

/// 图片 / 视频分轨处理的体积上限（字节）。
abstract final class ChatAttachmentLimits {
  static const int maxImageBytes = 20 * 1024 * 1024; // 20 MB
  static const int maxVideoBytes = 200 * 1024 * 1024; // 200 MB
}

class ChatAttachmentException implements Exception {
  ChatAttachmentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PickedChatAttachment {
  const PickedChatAttachment({
    required this.type,
    required this.stablePath,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final ChatAttachmentType type;
  final String stablePath;
  final String originalName;
  final String mimeType;
  final int sizeBytes;

  bool get isImage => type == ChatAttachmentType.image;
  bool get isVideo => type == ChatAttachmentType.video;
}

/// 聊天附件：图片与视频分轨选择、校验与落盘（视频不做全量读内存）。
abstract final class ChatAttachmentService {
  ChatAttachmentService._();

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  };

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.webm',
    '.m4v',
  };

  static const XTypeGroup _imageGroup = XTypeGroup(
    label: 'images',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    mimeTypes: [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/bmp',
    ],
  );

  /// Windows 上视频筛选以扩展名为准，避免 MIME 不匹配导致 mp4 选不中。
  static const XTypeGroup _videoGroup = XTypeGroup(
    label: 'videos',
    extensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'],
  );

  static Future<PickedChatAttachment?> pickImage() => _pickImage();

  static Future<PickedChatAttachment?> pickVideo() => _pickVideo();

  static Future<PickedChatAttachment?> _pickImage() async {
    final file = await openFile(acceptedTypeGroups: const [_imageGroup]);
    if (file == null) return null;

    final name = file.name;
    final ext = p.extension(name).toLowerCase();
    if (!_imageExtensions.contains(ext)) {
      throw ChatAttachmentException('请选择 JPG、PNG 等图片文件');
    }

    final mime = file.mimeType ?? _imageMimeFromExtension(ext);
    final preferredId = 'image_${DateTime.now().microsecondsSinceEpoch}';

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      _assertSize(bytes.length, ChatAttachmentLimits.maxImageBytes, '图片');
      return PickedChatAttachment(
        type: ChatAttachmentType.image,
        stablePath: 'data:$mime;base64,${base64Encode(bytes)}',
        originalName: name,
        mimeType: mime,
        sizeBytes: bytes.length,
      );
    }

    final sourcePath = file.path.trim();
    if (sourcePath.isEmpty) {
      throw ChatAttachmentException('无法读取图片路径');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ChatAttachmentException('找不到所选图片');
    }

    final sizeBytes = await source.length();
    _assertSize(sizeBytes, ChatAttachmentLimits.maxImageBytes, '图片');

    final stablePath = await ProfilePhotoStorage.copyIntoAppStorage(
      sourcePath,
      preferredId: preferredId,
    );

    return PickedChatAttachment(
      type: ChatAttachmentType.image,
      stablePath: stablePath,
      originalName: name,
      mimeType: mime,
      sizeBytes: sizeBytes,
    );
  }

  static Future<PickedChatAttachment?> _pickVideo() async {
    final file = await openFile(acceptedTypeGroups: const [_videoGroup]);
    if (file == null) return null;

    final name = file.name;
    final ext = p.extension(name).toLowerCase();
    if (!_videoExtensions.contains(ext)) {
      throw ChatAttachmentException('请选择 MP4、MOV 等视频文件');
    }

    final mime = file.mimeType ?? _videoMimeFromExtension(ext);
    final preferredId = 'video_${DateTime.now().microsecondsSinceEpoch}';

    if (kIsWeb) {
      // Web 仍走流式写入，避免一次性 base64 占满内存。
      final bytes = await file.readAsBytes();
      _assertSize(bytes.length, ChatAttachmentLimits.maxVideoBytes, '视频');
      final stablePath = await _writeBytesToAppStorage(
        bytes,
        extension: ext,
        preferredId: preferredId,
        subdir: 'chat_videos',
      );
      return PickedChatAttachment(
        type: ChatAttachmentType.video,
        stablePath: stablePath,
        originalName: name,
        mimeType: mime,
        sizeBytes: bytes.length,
      );
    }

    final sourcePath = file.path.trim();
    if (sourcePath.isEmpty) {
      throw ChatAttachmentException('无法读取视频路径');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ChatAttachmentException('找不到所选视频');
    }

    final sizeBytes = await source.length();
    _assertSize(sizeBytes, ChatAttachmentLimits.maxVideoBytes, '视频');

    // 视频只做文件复制，不 readAsBytes。
    final stablePath = await _copyFileToAppStorage(
      sourcePath,
      preferredId: preferredId,
      subdir: 'chat_videos',
    );

    return PickedChatAttachment(
      type: ChatAttachmentType.video,
      stablePath: stablePath,
      originalName: name,
      mimeType: mime,
      sizeBytes: sizeBytes,
    );
  }

  static void _assertSize(int bytes, int maxBytes, String label) {
    if (bytes > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).round();
      throw ChatAttachmentException('$label过大，请选择不超过 ${mb}MB 的文件');
    }
  }

  static String _imageMimeFromExtension(String ext) {
    return switch (ext) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.bmp' => 'image/bmp',
      _ => 'image/jpeg',
    };
  }

  static String _videoMimeFromExtension(String ext) {
    return switch (ext) {
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.avi' => 'video/x-msvideo',
      '.mkv' => 'video/x-matroska',
      '.m4v' => 'video/x-m4v',
      _ => 'video/mp4',
    };
  }

  static Future<String> _copyFileToAppStorage(
    String sourcePath, {
    required String preferredId,
    required String subdir,
  }) async {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('文件路径不能为空');
    }

    final source = File(trimmed);
    if (!await source.exists()) {
      throw FileSystemException('找不到文件', trimmed);
    }

    final dbPath = await LocalDatabase.getDatabasePathForDebug();
    final dir = Directory(p.join(p.dirname(dbPath), subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final extension = p.extension(trimmed);
    if (extension.isEmpty) {
      throw ChatAttachmentException('视频文件缺少扩展名');
    }
    final targetPath = p.join(dir.path, '$preferredId$extension');
    final copied = await source.copy(targetPath);
    return copied.absolute.path;
  }

  static Future<String> _writeBytesToAppStorage(
    List<int> bytes, {
    required String extension,
    required String preferredId,
    required String subdir,
  }) async {
    final dbPath = await LocalDatabase.getDatabasePathForDebug();
    final dir = Directory(p.join(p.dirname(dbPath), subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = extension.isEmpty ? '.mp4' : extension;
    final target = File(p.join(dir.path, '$preferredId$ext'));
    await target.writeAsBytes(bytes, flush: true);
    return target.absolute.path;
  }
}
