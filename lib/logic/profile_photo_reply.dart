import '../data/local_db/local_database.dart';
import '../data/models/profile_photo.dart';

/// 根据用户话术从 [profile_photos] 解析要展示的照片。
enum ProfilePhotoReplyStatus {
  notRequested,
  noPhotosInDb,
  noMatch,
  needsClarification,
  matched,
}

class ProfilePhotoReplyResult {
  const ProfilePhotoReplyResult({
    required this.status,
    this.photos = const [],
    this.clarifyMessage,
    this.candidateLabels = const [],
  });

  final ProfilePhotoReplyStatus status;
  final List<ProfilePhotoModel> photos;
  final String? clarifyMessage;
  final List<String> candidateLabels;
}

class ProfilePhotoReplyResolver {
  ProfilePhotoReplyResolver._();

  static final _intentPattern = RegExp(
    r'照片|相片|图片|看一下|看看|给我看|瞧瞧|翻出|找出来|有没有.*照|照.*看看',
  );

  static const _categoryHints = <String, ProfilePhotoCategory>{
    '头像': ProfilePhotoCategory.avatar,
    '老人头像': ProfilePhotoCategory.avatar,
    '家庭': ProfilePhotoCategory.family,
    '家人': ProfilePhotoCategory.family,
    '亲属': ProfilePhotoCategory.family,
    '经历': ProfilePhotoCategory.memory,
    '往事': ProfilePhotoCategory.memory,
    '记忆': ProfilePhotoCategory.memory,
    '日常': ProfilePhotoCategory.daily,
    '生活照': ProfilePhotoCategory.daily,
  };

  static String categoryLabel(ProfilePhotoCategory c) {
    return switch (c) {
      ProfilePhotoCategory.avatar => '老人头像',
      ProfilePhotoCategory.family => '家庭照片',
      ProfilePhotoCategory.memory => '经历照片',
      ProfilePhotoCategory.daily => '日常照片',
      ProfilePhotoCategory.other => '其他照片',
    };
  }

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

    ProfilePhotoCategory? forcedCategory;
    for (final e in _categoryHints.entries) {
      if (text.contains(e.key)) {
        forcedCategory = e.value;
        break;
      }
    }

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

    final tokens = _tokensFromUserText(text);
    final scored = <_ScoredPhoto>[];
    for (final photo in all) {
      if (forcedCategory != null && photo.category != forcedCategory) {
        continue;
      }
      final score = _scorePhoto(
        photo,
        text: text,
        tokens: tokens,
        familyNames: familyNames,
      );
      if (score > 0) {
        scored.add(_ScoredPhoto(photo, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) {
      // 有看照片意图但未命中标签：若仅 1～3 张则全部展示，否则请用户说明
      final pool = forcedCategory == null
          ? all
          : all.where((p) => p.category == forcedCategory).toList();
      if (pool.length == 1) {
        return ProfilePhotoReplyResult(
          status: ProfilePhotoReplyStatus.matched,
          photos: pool,
        );
      }
      if (pool.length <= 3 && tokens.isEmpty) {
        return ProfilePhotoReplyResult(
          status: ProfilePhotoReplyStatus.matched,
          photos: pool.take(3).toList(),
        );
      }
      return ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.noMatch,
      );
    }

    final top = scored.first.score;
    final winners = scored.where((s) => s.score >= top - 8).toList();
    if (winners.length > 1 && winners[1].score >= top - 3) {
      final labels = winners.take(4).map((s) => describePhoto(s.photo)).toList();
      return ProfilePhotoReplyResult(
        status: ProfilePhotoReplyStatus.needsClarification,
        clarifyMessage:
            '我找到好几张可能对得上的照片，您想看哪一张？\n${labels.map((l) => '· $l').join('\n')}\n您可以说得更具体一点，比如人物名字或「家庭照片」。',
        candidateLabels: labels,
      );
    }

    return ProfilePhotoReplyResult(
      status: ProfilePhotoReplyStatus.matched,
      photos: winners.take(3).map((s) => s.photo).toList(),
    );
  }

  static List<String> _tokensFromUserText(String text) {
    final stop = RegExp(
      r'照片|相片|图片|看看|看一下|给我看|有没有|一张|几张|翻|找|的|了|吗|呢|啊|吧|请|想|要',
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
  }) {
    var score = 0;
    final blob = [
      categoryLabel(photo.category),
      photo.caption ?? '',
      photo.peopleInvolved ?? '',
      photo.location ?? '',
      photo.photoTime ?? '',
      if (photo.familyMemberId != null)
        familyNames[photo.familyMemberId!] ?? '',
    ].join(' ');

    for (final hint in _categoryHints.keys) {
      if (text.contains(hint) && blob.contains(hint)) {
        score += 12;
      }
    }

    for (final token in tokens) {
      if (blob.contains(token)) score += 18;
      if (photo.caption?.contains(token) == true) score += 10;
      if (photo.peopleInvolved?.contains(token) == true) score += 14;
    }

    if (photo.isFavorite) score += 2;
    return score;
  }
}

class _ScoredPhoto {
  const _ScoredPhoto(this.photo, this.score);
  final ProfilePhotoModel photo;
  final int score;
}
