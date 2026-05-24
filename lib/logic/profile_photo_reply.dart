import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/photo_intent_plan.dart';
import '../data/models/profile_photo.dart';
import '../data/repositories/chat_repository.dart';
import 'user_archive_cache.dart';

enum ProfilePhotoReplyStatus {
  notRequested,
  noPhotosInDb,
  noMatch,
  exhausted,
  matched,
}

class ProfilePhotoReplyResult {
  const ProfilePhotoReplyResult({
    required this.status,
    this.photos = const [],
    this.queryText,
    this.requestedCount = 0,
    this.planSummary = '',
  });

  final ProfilePhotoReplyStatus status;
  final List<ProfilePhotoModel> photos;
  final String? queryText;
  final int requestedCount;
  final String planSummary;

  bool get photoRequested => status != ProfilePhotoReplyStatus.notRequested;
}

class ProfilePhotoReplyResolver {
  ProfilePhotoReplyResolver._();

  static const _maxPhotosPerBatch = 24;

  static final _intentPattern = RegExp(
    r'照片|相片|图片|相册|图|看一下|看看|给我看|瞧瞧|翻出|找出来|有没有.*照|照.*看看|想看|输出|展示',
  );

  static final _rejectionPattern = RegExp(
    r'不是这(张|个|幅|种)?|不对|不是的|换一张|另一张|再看看别的|不是我要的|不要这张|不是那张|不要.*照',
  );

  static bool isRejectionPhrase(String text) =>
      _rejectionPattern.hasMatch(text.trim());

  static bool hasPhotoIntent(String text) =>
      text.trim().isNotEmpty && _intentPattern.hasMatch(text.trim());

  static String categoryLabel(ProfilePhotoCategory c) =>
      ProfilePhotoCategoryLabels.label(c);

  static String describePhoto(ProfilePhotoModel photo) {
    final parts = <String>[categoryLabel(photo.category)];
    final cap = photo.caption?.trim();
    if (cap != null && cap.isNotEmpty) parts.add(cap);
    final people = photo.peopleInvolved?.trim();
    if (people != null && people.isNotEmpty) parts.add('人物：$people');
    final when = photo.photoTime?.trim();
    if (when != null && when.isNotEmpty) parts.add(when);
    return parts.join(' · ');
  }

  /// 预读 catalog + 大模型判定需求 + 本地匹配（可较慢）。
  static Future<ProfilePhotoReplyResult> resolve({
    required String userText,
    required UserArchiveCache cache,
    required ChatRepository repository,
    Set<String> excludePhotoIds = const {},
    bool isRejection = false,
    String? previousQueryText,
  }) async {
    final text = userText.trim();
    final broadIntent = hasPhotoIntent(text) || isRejection;
    if (!broadIntent) {
      return const ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.notRequested,
      );
    }

    if (cache.photos.isEmpty) {
      return ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.noPhotosInDb,
        queryText: text,
      );
    }

    PhotoIntentPlan plan;
    try {
      plan = await repository
          .analyzePhotoDisplayIntent(
            userMessage: text,
            photoCatalog: cache.buildPhotoCatalogForLlm(),
            isRejectionContinuation: isRejection,
            previousUserQuery: previousQueryText,
            recentlyShownPhotoIds: excludePhotoIds.toList(),
          )
          .timeout(const Duration(seconds: 60));
      debugPrint(
        '[PhotoReply] LLM plan want=${plan.wantPhotos} '
        'inc=${plan.includeFilters.length} exc=${plan.excludeFilters.length} '
        '${plan.reasonSummary}',
      );
    } catch (e, st) {
      debugPrint('[PhotoReply] LLM 选图判定失败，规则回退: $e\n$st');
      return _resolveWithRules(
        userText: text,
        cache: cache,
        excludePhotoIds: excludePhotoIds,
        isRejection: isRejection,
      );
    }

    final planLooksEmpty = !plan.wantPhotos &&
        plan.includeFilters.isEmpty &&
        plan.excludeFilters.isEmpty;
    if (planLooksEmpty && (hasPhotoIntent(text) || isRejection)) {
      return _resolveWithRules(
        userText: text,
        cache: cache,
        excludePhotoIds: excludePhotoIds,
        isRejection: isRejection,
      );
    }

    if (!plan.wantPhotos && !isRejection) {
      return const ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.notRequested,
      );
    }

    if (!plan.wantPhotos && isRejection) {
      plan = PhotoIntentPlan(
        wantPhotos: true,
        includeFilters: plan.includeFilters,
        excludeFilters: plan.excludeFilters,
        maxPhotos: plan.maxPhotos,
        reasonSummary: plan.reasonSummary,
      );
    }

    var matched = _applyPlan(
      cache.photos,
      plan,
      excludePhotoIds: excludePhotoIds,
    );

    if (matched.isEmpty) {
      matched = _applyPlan(
        cache.photos,
        plan,
        excludePhotoIds: excludePhotoIds,
        loose: true,
      );
    }

    if (matched.isEmpty) {
      if (excludePhotoIds.isNotEmpty && isRejection) {
        return ProfilePhotoReplyResult(
          status: ProfilePhotoReplyStatus.exhausted,
          queryText: previousQueryText ?? text,
          planSummary: plan.reasonSummary,
        );
      }
      return ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.noMatch,
        queryText: text,
        planSummary: plan.reasonSummary,
      );
    }

    final limit = plan.maxPhotos > 0
        ? plan.maxPhotos.clamp(1, _maxPhotosPerBatch)
        : _decideOutputCount(
            text,
            matched.length,
            isRejection: isRejection,
          );
    final batch = matched.take(limit).toList();

    return ProfilePhotoReplyResult(
      status: ProfilePhotoReplyStatus.matched,
      photos: batch,
      queryText: text,
      requestedCount: limit,
      planSummary: plan.reasonSummary,
    );
  }

  static List<ProfilePhotoModel> _applyPlan(
    List<ProfilePhotoModel> all,
    PhotoIntentPlan plan, {
    required Set<String> excludePhotoIds,
    bool loose = false,
  }) {
    var pool = all.where((p) => !excludePhotoIds.contains(p.id)).toList();

    if (plan.excludeFilters.isNotEmpty) {
      pool = pool
          .where((p) => !_matchesAnyFilter(p, plan.excludeFilters, loose: loose))
          .toList();
    }

    final hasInclude = plan.includeFilters.any((f) => !f.isEmpty);
    if (hasInclude) {
      pool = pool
          .where((p) => _matchesAnyFilter(p, plan.includeFilters, loose: loose))
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
    ProfilePhotoModel photo,
    List<PhotoIntentFilter> filters, {
    bool loose = false,
  }) {
    for (final f in filters) {
      if (f.isEmpty) continue;
      if (_matchesFilter(photo, f, loose: loose)) return true;
    }
    return false;
  }

  static bool _matchesFilter(
    ProfilePhotoModel photo,
    PhotoIntentFilter filter, {
    bool loose = false,
  }) {
    if (filter.photoIds.contains(photo.id)) return true;

    for (final c in filter.categories) {
      final cat = _categoryFromToken(c);
      if (cat != null && photo.category == cat) return true;
    }

    final blob = _photoSearchBlob(photo);
    for (final kw in [...filter.keywords, ...filter.labels]) {
      final k = kw.trim();
      if (k.length < 2) continue;
      if (blob.contains(k)) return true;
      if (loose && k.length >= 2 && _fuzzyContains(blob, k)) return true;
    }
    return false;
  }

  static bool _fuzzyContains(String blob, String kw) => blob.contains(kw);

  static ProfilePhotoCategory? _categoryFromToken(String token) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final c in ProfilePhotoCategory.values) {
      if (c.value == t) return c;
    }
    return ProfilePhotoCategoryLabels.categoryFromUserPhrase(token);
  }

  static String _photoSearchBlob(ProfilePhotoModel photo) {
    return [
      categoryLabel(photo.category),
      photo.category.value,
      photo.caption ?? '',
      photo.peopleInvolved ?? '',
      photo.location ?? '',
      photo.photoTime ?? '',
      photo.id,
    ].join(' ');
  }

  static Future<ProfilePhotoReplyResult> _resolveWithRules({
    required String userText,
    required UserArchiveCache cache,
    required Set<String> excludePhotoIds,
    required bool isRejection,
  }) async {
    final text = userText.trim();
    if (!shouldOutputPhotos(text, isRejection: isRejection)) {
      return const ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.notRequested,
      );
    }
    final forcedCategory = ProfilePhotoCategoryLabels.categoryFromUserPhrase(text);
    var pool = forcedCategory == null
        ? List<ProfilePhotoModel>.from(cache.photos)
        : cache.photos.where((p) => p.category == forcedCategory).toList();
    pool = pool.where((p) => !excludePhotoIds.contains(p.id)).toList();
    if (pool.isEmpty) {
      return ProfilePhotoReplyResult(
        status: excludePhotoIds.isNotEmpty
            ? ProfilePhotoReplyStatus.exhausted
            : ProfilePhotoReplyStatus.noMatch,
        queryText: text,
      );
    }
    final limit = _decideOutputCount(text, pool.length, isRejection: isRejection);
    return ProfilePhotoReplyResult(
      status: ProfilePhotoReplyStatus.matched,
      photos: pool.take(limit).toList(),
      queryText: text,
      requestedCount: limit,
    );
  }

  static bool shouldOutputPhotos(String userText, {bool isRejection = false}) {
    final t = userText.trim();
    if (t.isEmpty) return false;
    if (isRejection) return true;
    return hasPhotoIntent(t);
  }

  static int _decideOutputCount(
    String userText,
    int available, {
    bool isRejection = false,
  }) {
    if (available <= 0) return 0;
    final cap = available > _maxPhotosPerBatch ? _maxPhotosPerBatch : available;
    final t = userText.trim();

    if (isRejection) {
      if (RegExp(r'几张|多张|一些|都').hasMatch(t)) return cap < 3 ? cap : 3;
      return 1;
    }

    if (RegExp(r'全部|所有|都给|都看看').hasMatch(t)) return cap;

    final digit = RegExp(r'(\d+)\s*张').firstMatch(t);
    if (digit != null) {
      final n = int.tryParse(digit.group(1) ?? '') ?? 1;
      return n.clamp(1, cap);
    }

    if (t.contains('两张') || t.contains('2张')) return cap < 2 ? cap : 2;
    if (t.contains('三张') || t.contains('3张')) return cap < 3 ? cap : 3;
    if (t.contains('一张') || t.contains('这张')) return 1;

    if (t.contains('几张') || t.contains('多张')) return cap < 3 ? cap : 3;

    return cap;
  }
}
