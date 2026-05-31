import 'package:flutter/foundation.dart';

import '../data/local_db/local_database.dart';
import '../data/models/profile_photo.dart';
import '../data/models/profile_video.dart';

/// 首次对话前从本地库预读的档案快照（文字 + 照片 + 视频索引）。
class UserArchiveCache {
  UserArchiveCache({
    required this.ownerUserId,
    required this.user,
    required this.memoryContextLines,
    required this.elderProfileBrief,
    required this.photos,
    required this.videos,
    required this.familyMembers,
    required this.nearbyPeople,
    required this.familyNamesById,
  });

  final String ownerUserId;
  final Map<String, dynamic>? user;
  final List<String> memoryContextLines;
  final String elderProfileBrief;
  /// 仅图片（不含视频）。
  final List<ProfilePhotoModel> photos;
  final List<ProfileVideoModel> videos;
  final List<Map<String, dynamic>> familyMembers;
  final List<Map<String, dynamic>> nearbyPeople;
  final Map<int, String> familyNamesById;

  static Future<UserArchiveCache> load(String ownerUserId) async {
    debugPrint('[UserArchiveCache] 预读取档案 owner=$ownerUserId');
    final bundle = await LocalDatabase.queryStoredUserDataForUser(ownerUserId);
    final lines =
        await LocalDatabase.queryMemoryContextLinesForUser(ownerUserId);
    final brief = _composeElderProfileBrief(bundle.user, lines);
    final familyNames = <int, String>{};
    for (final r in bundle.familyMembers) {
      final id = (r['id'] as num?)?.toInt();
      final name = (r['name'] as String?)?.trim();
      if (id != null && name != null && name.length >= 2) {
        familyNames[id] = name;
      }
    }
    final photos = bundle.profilePhotoRows
        .map(ProfilePhotoModel.fromMap)
        .where((p) => !p.isVideo)
        .toList(growable: false);
    final videos = bundle.profileVideoRows
        .map(ProfileVideoModel.fromMap)
        .toList(growable: false);
    debugPrint(
      '[UserArchiveCache] 完成：照片 ${photos.length} 张，'
      '视频 ${videos.length} 段，档案行 ${lines.length}，家人 ${bundle.familyMembers.length}',
    );
    return UserArchiveCache(
      ownerUserId: ownerUserId,
      user: bundle.user,
      memoryContextLines: lines,
      elderProfileBrief: brief,
      photos: photos,
      videos: videos,
      familyMembers: bundle.familyMembers,
      nearbyPeople: bundle.nearbyPeople,
      familyNamesById: familyNames,
    );
  }

  static String _composeElderProfileBrief(
    Map<String, dynamic>? user,
    List<String> lines,
  ) {
    final parts = <String>[];
    if (user != null) {
      void add(String label, String key) {
        final v = (user[key] as String?)?.trim();
        if (v != null && v.isNotEmpty) parts.add(label.isEmpty ? v : '$label$v');
      }

      add('', 'name');
      add('', 'birth_year');
      add('籍贯', 'hometown');
      add('职业', 'career');
      add('爱好', 'hobbies');
      add('性格', 'personality');
    }
    var brief = parts.isEmpty ? '（暂无详细档案）' : parts.join('，');
    final storedBody = lines
        .where((l) => !l.contains('暂无'))
        .map((l) => l.startsWith('- ') ? l.substring(2) : l)
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
    if (storedBody.isEmpty) return brief;
    if (brief == '（暂无详细档案）') return storedBody;
    return '$brief\n$storedBody';
  }

  String buildPhotoCatalogForLlm() {
    if (photos.isEmpty) return '（照片库为空）';
    final buf = StringBuffer();
    for (final p in photos) {
      final fav = p.isFavorite ? '是' : '否';
      buf.writeln(
        'id=${p.id} | 类型=图片'
        ' | 分类=${ProfilePhotoCategoryLabels.label(p.category)}'
        '(${p.category.value}) | 说明=${p.caption ?? ''}'
        ' | 人物=${p.peopleInvolved ?? ''}'
        ' | 地点=${p.location ?? ''}'
        ' | 时间=${p.photoTime ?? ''}'
        ' | 重点=$fav',
      );
    }
    return buf.toString().trim();
  }

  String buildVideoCatalogForLlm() {
    if (videos.isEmpty) return '（视频库为空）';
    final buf = StringBuffer();
    for (final v in videos) {
      final fav = v.isFavorite ? '是' : '否';
      buf.writeln(
        'id=${v.id} | 类型=视频'
        ' | 分类=${v.category.value}'
        ' | 说明=${v.caption ?? ''}'
        ' | 人物=${v.peopleInvolved ?? ''}'
        ' | 地点=${v.location ?? ''}'
        ' | 时间=${v.videoTime ?? ''}'
        ' | 重点=$fav',
      );
    }
    return buf.toString().trim();
  }

  String buildKnownNamesHint() {
    final lines = <String>[];
    for (final r in familyMembers.take(12)) {
      final name = (r['name'] as String?)?.trim() ?? '';
      if (name.length < 2) continue;
      final rel = (r['relation'] as String?)?.trim() ?? '';
      lines.add(rel.isEmpty ? name : '$rel $name');
    }
    for (final r in nearbyPeople.take(12)) {
      final name = (r['name'] as String?)?.trim() ?? '';
      if (name.length < 2) continue;
      final rel = (r['relation'] as String?)?.trim() ?? '';
      lines.add(rel.isEmpty ? name : '$rel $name');
    }
    return lines.join('；');
  }
}
