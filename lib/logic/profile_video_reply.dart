import 'package:flutter/foundation.dart';

import '../data/models/photo_intent_plan.dart';
import '../data/models/profile_video.dart';
import '../data/repositories/chat_repository.dart';
import 'user_archive_cache.dart';

enum ProfileVideoReplyStatus {
  notRequested,
  noVideosInDb,
  noMatch,
  exhausted,
  matched,
}

class ProfileVideoReplyResult {
  const ProfileVideoReplyResult({
    required this.status,
    this.videos = const [],
    this.queryText,
    this.requestedCount = 0,
  });

  final ProfileVideoReplyStatus status;
  final List<ProfileVideoModel> videos;
  final String? queryText;
  final int requestedCount;

  bool get videoRequested => status != ProfileVideoReplyStatus.notRequested;
}

class ProfileVideoReplyResolver {
  ProfileVideoReplyResolver._();

  static const _maxVideosPerBatch = 3;

  static final _videoIntentPattern = RegExp(
    r'视频|录像|影片|短片|vlog|VLOG|看一下.*视频|看看.*视频|给我看.*视频|有没有.*视频',
  );

  static final _rejectionPattern = RegExp(
    r'不是这(个|段|条|种)?|不对|不是的|换一段|另一个|再看看别的|不是我要的|不要这段|不要.*视频',
  );

  static bool isRejectionPhrase(String text) =>
      _rejectionPattern.hasMatch(text.trim());

  static bool hasVideoIntent(String text) {
    final t = text.trim();
    return t.isNotEmpty && _videoIntentPattern.hasMatch(t);
  }

  static String describeVideo(ProfileVideoModel video) {
    final parts = <String>['视频'];
    final cap = video.caption?.trim();
    if (cap != null && cap.isNotEmpty) parts.add(cap);
    final people = video.peopleInvolved?.trim();
    if (people != null && people.isNotEmpty) parts.add('人物：$people');
    final when = video.videoTime?.trim();
    if (when != null && when.isNotEmpty) parts.add(when);
    return parts.join(' · ');
  }

  static Future<ProfileVideoReplyResult> resolve({
    required String userText,
    required UserArchiveCache cache,
    required ChatRepository repository,
    Set<String> excludeVideoIds = const {},
    bool isRejection = false,
    String? previousQueryText,
  }) async {
    final text = userText.trim();
    if (!hasVideoIntent(text) && !isRejection) {
      return const ProfileVideoReplyResult(
        status: ProfileVideoReplyStatus.notRequested,
      );
    }

    if (cache.videos.isEmpty) {
      return ProfileVideoReplyResult(
        status: ProfileVideoReplyStatus.noVideosInDb,
        queryText: text,
      );
    }

    PhotoIntentPlan plan;
    try {
      plan = await repository
          .analyzePhotoDisplayIntent(
            userMessage: text,
            photoCatalog: cache.buildVideoCatalogForLlm(),
            isRejectionContinuation: isRejection,
            previousUserQuery: previousQueryText,
            recentlyShownPhotoIds: excludeVideoIds.toList(),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e, st) {
      debugPrint('[VideoReply] LLM 选视频判定失败，规则回退: $e\n$st');
      return _resolveWithRules(
        userText: text,
        cache: cache,
        excludeVideoIds: excludeVideoIds,
        isRejection: isRejection,
      );
    }

    final planLooksEmpty = !plan.wantPhotos &&
        plan.includeFilters.isEmpty &&
        plan.excludeFilters.isEmpty;
    if (planLooksEmpty && (hasVideoIntent(text) || isRejection)) {
      return _resolveWithRules(
        userText: text,
        cache: cache,
        excludeVideoIds: excludeVideoIds,
        isRejection: isRejection,
      );
    }

    if (!plan.wantPhotos && !isRejection) {
      return const ProfileVideoReplyResult(
        status: ProfileVideoReplyStatus.notRequested,
      );
    }

    var matched = _applyPlan(
      cache.videos,
      plan,
      excludeVideoIds: excludeVideoIds,
    );
    if (matched.isEmpty) {
      matched = _applyPlan(
        cache.videos,
        plan,
        excludeVideoIds: excludeVideoIds,
        loose: true,
      );
    }

    if (matched.isEmpty) {
      if (excludeVideoIds.isNotEmpty && isRejection) {
        return ProfileVideoReplyResult(
          status: ProfileVideoReplyStatus.exhausted,
          queryText: previousQueryText ?? text,
        );
      }
      return ProfileVideoReplyResult(
        status: ProfileVideoReplyStatus.noMatch,
        queryText: text,
      );
    }

    final limit = plan.maxPhotos > 0
        ? plan.maxPhotos.clamp(1, _maxVideosPerBatch)
        : _decideOutputCount(text, matched.length, isRejection: isRejection);

    return ProfileVideoReplyResult(
      status: ProfileVideoReplyStatus.matched,
      videos: matched.take(limit).toList(),
      queryText: text,
      requestedCount: limit,
    );
  }

  static List<ProfileVideoModel> _applyPlan(
    List<ProfileVideoModel> all,
    PhotoIntentPlan plan, {
    required Set<String> excludeVideoIds,
    bool loose = false,
  }) {
    var pool = all.where((v) => !excludeVideoIds.contains(v.id)).toList();

    if (plan.excludeFilters.isNotEmpty) {
      pool = pool
          .where(
            (v) => !_matchesAnyFilter(v, plan.excludeFilters, loose: loose),
          )
          .toList();
    }

    final hasInclude = plan.includeFilters.any((f) => !f.isEmpty);
    if (hasInclude) {
      pool = pool
          .where(
            (v) => _matchesAnyFilter(v, plan.includeFilters, loose: loose),
          )
          .toList();
    }

    pool.sort((a, b) {
      final fav = (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0);
      if (fav != 0) return fav;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return pool;
  }

  static bool _matchesAnyFilter(
    ProfileVideoModel video,
    List<PhotoIntentFilter> filters, {
    bool loose = false,
  }) {
    for (final f in filters) {
      if (f.isEmpty) continue;
      if (f.photoIds.contains(video.id)) return true;
      final blob = _videoSearchBlob(video);
      for (final kw in [...f.keywords, ...f.labels]) {
        final k = kw.trim();
        if (k.length >= 2 && blob.contains(k)) return true;
        if (loose && k.length >= 2 && blob.contains(k)) return true;
      }
    }
    return false;
  }

  static String _videoSearchBlob(ProfileVideoModel video) {
    return [
      video.category.value,
      video.caption ?? '',
      video.peopleInvolved ?? '',
      video.location ?? '',
      video.videoTime ?? '',
      video.id,
    ].join(' ');
  }

  static Future<ProfileVideoReplyResult> _resolveWithRules({
    required String userText,
    required UserArchiveCache cache,
    required Set<String> excludeVideoIds,
    required bool isRejection,
  }) async {
    final text = userText.trim();
    if (!hasVideoIntent(text) && !isRejection) {
      return const ProfileVideoReplyResult(
        status: ProfileVideoReplyStatus.notRequested,
      );
    }
    var pool =
        cache.videos.where((v) => !excludeVideoIds.contains(v.id)).toList();
    if (pool.isEmpty) {
      return ProfileVideoReplyResult(
        status: excludeVideoIds.isNotEmpty
            ? ProfileVideoReplyStatus.exhausted
            : ProfileVideoReplyStatus.noMatch,
        queryText: text,
      );
    }
    final limit = _decideOutputCount(text, pool.length, isRejection: isRejection);
    return ProfileVideoReplyResult(
      status: ProfileVideoReplyStatus.matched,
      videos: pool.take(limit).toList(),
      queryText: text,
      requestedCount: limit,
    );
  }

  static int _decideOutputCount(
    String userText,
    int available, {
    bool isRejection = false,
  }) {
    if (available <= 0) return 0;
    final cap = available > _maxVideosPerBatch ? _maxVideosPerBatch : available;
    final t = userText.trim();

    if (isRejection) return 1;

    if (RegExp(r'全部|所有|都给|都看看').hasMatch(t)) {
      return cap < 3 ? cap : 3;
    }

    final digit = RegExp(r'(\d+)\s*(段|个)').firstMatch(t);
    if (digit != null) {
      final n = int.tryParse(digit.group(1) ?? '') ?? 1;
      return n.clamp(1, cap);
    }

    if (t.contains('两段') || t.contains('2段')) return cap < 2 ? cap : 2;
    if (t.contains('三段') || t.contains('3段')) return cap < 3 ? cap : 3;

    return 1;
  }
}
