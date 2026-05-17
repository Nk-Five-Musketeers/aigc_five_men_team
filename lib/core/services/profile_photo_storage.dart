import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../data/local_db/local_database.dart';

class ProfilePhotoStorage {
  ProfilePhotoStorage._();

  static Future<String> copyIntoAppStorage(
    String sourcePath, {
    String? preferredId,
  }) async {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('照片路径不能为空');
    }
    if (kIsWeb) {
      return trimmed;
    }

    final source = File(trimmed);
    if (!await source.exists()) {
      throw FileSystemException('找不到照片文件', trimmed);
    }

    final dbPath = await LocalDatabase.getDatabasePathForDebug();
    final dir = Directory(p.join(p.dirname(dbPath), 'profile_photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final extension = p.extension(trimmed);
    final safeId =
        preferredId ?? 'photo_${DateTime.now().microsecondsSinceEpoch}';
    final copied = await source.copy(p.join(dir.path, '$safeId$extension'));
    return copied.path;
  }
}
