import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// 本地媒体文件路径规范化，确保播放器能定位到真实文件。
abstract final class LocalMediaPath {
  LocalMediaPath._();

  static Future<String> resolveForPlayback(String rawPath) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      throw StateError('视频路径为空');
    }
    if (kIsWeb || trimmed.startsWith('data:')) {
      return trimmed;
    }
    final file = File(trimmed);
    final absolute = file.absolute;
    if (!await absolute.exists()) {
      throw StateError('找不到视频文件：${absolute.path}');
    }
    final length = await absolute.length();
    if (length <= 0) {
      throw StateError('视频文件为空或已损坏');
    }
    return absolute.path;
  }
}
