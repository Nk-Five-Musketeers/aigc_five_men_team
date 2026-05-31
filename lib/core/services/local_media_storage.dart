import 'dart:io';

import 'package:flutter/foundation.dart';

/// 删除本地图片/视频文件（data URI 与 Web 跳过）。
abstract final class LocalMediaStorage {
  LocalMediaStorage._();

  static Future<void> deleteFileIfExists(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    if (kIsWeb || path.startsWith('data:')) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[LocalMediaStorage] 删除文件失败 ($path): $e');
    }
  }

  static Future<void> deleteFilesIfExist(Iterable<String?> paths) async {
    for (final path in paths) {
      await deleteFileIfExists(path);
    }
  }
}
