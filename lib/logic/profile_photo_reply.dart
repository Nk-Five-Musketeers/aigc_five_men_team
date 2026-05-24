import '../data/local_db/local_database.dart';
import '../data/models/profile_photo.dart';

/// 根据用户话术从 [profile_photos] 解析要展示的照片。
enum ProfilePhotoReplyStatus {
  /// 未表达看照片意图。
  notRequested,

  /// 有看照片意图，但库里没有任何照片。
  noPhotosInDb,

  /// 有看照片意图，模糊匹配后仍无法选出可展示条目。
  noMatch,

  /// 已选出可展示的照片（含模糊匹配）。
  matched,
}

class ProfilePhotoReplyResult {
  const ProfilePhotoReplyResult({
    required this.status,
    this.photos = const [],
  });

  final ProfilePhotoReplyStatus status;
  final List<ProfilePhotoModel> photos;

  /// 用户是否在要照片（含模糊说法，如「看看」「给我看」）。
  bool get photoRequested => status != ProfilePhotoReplyStatus.notRequested;
}

class ProfilePhotoReplyResolver {
  ProfilePhotoReplyResolver._();

  static final _intentPattern = RegExp(
    r'照片|相片|图片|相册|图|看一下|看看|给我看|瞧瞧|翻出|找出来|有没有.*照|照.*看看|想看',
  );

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

  static Future<ProfilePhotoReplyResult> resolve({
    required String ownerUserId,
    required String userText,
  }) async {
    final text = userText.trim();
    if (text.isEmpty || !_intentPattern.hasMatch(text)) {
      return const ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.notRequested,
      );
    }

    final all = await LocalDatabase.listProfilePhotosForUser(ownerUserId);
    if (all.isEmpty) {
      return const ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.noPhotosInDb,
      );
    }

    final forcedCategory = ProfilePhotoCategoryLabels.categoryFromUserPhrase(text);

    final familyRows =
        await LocalDatabase.listFamilyMembersForUser(ownerUserId);
    final familyNames = <int, String>{};
    for (final r in familyRows) {
      final id = (r['id'] as num?)?.toInt();
      final name = (r['name'] as String?)?.trim();
      if (id != null && name != null && name.length >= 2) {
        familyNames[id] = name;
      }
    }

    final wantsSeveral = text.contains('几张') ||
        text.contains('多') ||
        text.contains('都') ||
        text.contains('全部');

    var pool = forcedCategory == null
        ? all
        : all.where((p) => p.category == forcedCategory).toList();

    // 用户点了类别但库里该分类为空：在全库中按类别标签再筛一次（防历史数据 category 填错）
    if (pool.isEmpty && forcedCategory != null) {
      pool = all
          .where((p) =>
              ProfilePhotoCategoryLabels.phraseIndicatesCategory(
                '${ProfilePhotoCategoryLabels.label(p.category)} $text',
                forcedCategory,
              ))
          .toList();
    }

    if (pool.isEmpty) {
      return const ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.noMatch,
      );
    }

    final tokens = _tokensFromUserText(text);
    final scored = <_ScoredPhoto>[];
    for (final photo in pool) {
      final score = _scorePhoto(
        photo,
        text: text,
        tokens: tokens,
        familyNames: familyNames,
        forcedCategory: forcedCategory,
      );
      scored.add(_ScoredPhoto(photo, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    final maxCount = wantsSeveral ? 3 : 1;
    final topScore = scored.first.score;

    if (topScore >= 16) {
      final picked =
          _pickFromScored(scored, maxCount: maxCount, minScore: topScore - 10);
      if (picked.isNotEmpty) {
        return ProfilePhotoReplyResult(
          status: ProfilePhotoReplyStatus.matched,
          photos: picked,
        );
      }
    }

    if (topScore > 0) {
      final picked =
          _pickFromScored(scored, maxCount: wantsSeveral ? 3 : 2, minScore: 1);
      if (picked.isNotEmpty) {
        return ProfilePhotoReplyResult(
          status: ProfilePhotoReplyStatus.matched,
          photos: picked,
        );
      }
    }

    if (pool.length <= 3) {
      return ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.matched,
        photos: pool.take(3).toList(),
      );
    }

    if (forcedCategory != null) {
      final inCategory = pool.where((p) => p.category == forcedCategory).toList();
      if (inCategory.isNotEmpty) {
        return ProfilePhotoReplyResult(
          status: ProfilePhotoReplyStatus.matched,
          photos: inCategory.take(wantsSeveral ? 3 : 1).toList(),
        );
      }
    }

    final fuzzy = pool.take(wantsSeveral ? 3 : 1).toList();
    return ProfilePhotoReplyResult(
      status: ProfilePhotoReplyStatus.matched,
      photos: fuzzy,
    );
  }

  static List<ProfilePhotoModel> _pickFromScored(
    List<_ScoredPhoto> scored, {
    required int maxCount,
    required int minScore,
  }) {
    final out = <ProfilePhotoModel>[];
    for (final s in scored) {
      if (s.score < minScore) break;
      out.add(s.photo);
      if (out.length >= maxCount) break;
    }
    return out;
  }

  static List<String> _tokensFromUserText(String text) {
    final stop = RegExp(
      r'照片|相片|图片|相册|看看|看一下|给我看|有没有|一张|几张|翻|找|的|了|吗|呢|啊|吧|请|想|要|想看|头像|日常|家庭|经历|老人',
    );
    var t = text.replaceAll(stop, ' ');
    t = t.replaceAll(RegExp(r'[\s，,。！？；、]+'), ' ');
    return t
        .split(' ')
        .map((s) => s.trim())
        .where((s) => s.length >= 2)
        .toList();
  }

  static int _scorePhoto(
    ProfilePhotoModel photo, {
    required String text,
    required List<String> tokens,
    required Map<int, String> familyNames,
    ProfilePhotoCategory? forcedCategory,
  }) {
    var score = 0;
    final blob = [
      categoryLabel(photo.category),
      photo.category.value,
      photo.caption ?? '',
      photo.peopleInvolved ?? '',
      photo.location ?? '',
      photo.photoTime ?? '',
      if (photo.familyMemberId != null)
        familyNames[photo.familyMemberId!] ?? '',
    ].join(' ');

    if (forcedCategory != null && photo.category == forcedCategory) {
      score += 48;
    } else if (ProfilePhotoCategoryLabels.phraseIndicatesCategory(
      text,
      photo.category,
    )) {
      score += 36;
    }

    for (final alias in ProfilePhotoCategoryLabels.searchAliases[photo.category] ??
        const []) {
      if (alias.length >= 2 && text.contains(alias)) {
        score += 20;
      }
    }

    for (final token in tokens) {
      if (blob.contains(token)) score += 18;
      if (photo.caption?.contains(token) == true) score += 10;
      if (photo.peopleInvolved?.contains(token) == true) score += 14;
    }

    if (photo.isFavorite) score += 3;
    return score;
  }
}

class _ScoredPhoto {
  const _ScoredPhoto(this.photo, this.score);
  final ProfilePhotoModel photo;
  final int score;
}
