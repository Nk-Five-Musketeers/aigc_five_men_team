class MemoryAlbum {
  const MemoryAlbum({
    required this.albumId,
    required this.albumTitle,
    required this.albumSubtitle,
    required this.cover,
    required this.opening,
    required this.elderProfileCard,
    required this.chapters,
    required this.timeline,
    required this.ending,
    required this.familyQuestions,
    required this.notes,
    required this.narration,
  });

  final String albumId;
  final String albumTitle;
  final String albumSubtitle;
  final AlbumCover cover;
  final AlbumText opening;
  final ElderProfileCard elderProfileCard;
  final List<MemoryAlbumChapter> chapters;
  final List<MemoryTimelineEntry> timeline;
  final AlbumText ending;
  final List<FamilyQuestion> familyQuestions;
  final AlbumNotes notes;
  final MemoryAlbumNarration narration;

  bool get hasContent {
    return elderProfileCard.profileItems.isNotEmpty ||
        chapters.any((chapter) => chapter.items.isNotEmpty) ||
        timeline.isNotEmpty;
  }

  MemoryAlbum copyWith({
    String? albumTitle,
    String? albumSubtitle,
    AlbumCover? cover,
    AlbumText? opening,
    ElderProfileCard? elderProfileCard,
    List<MemoryAlbumChapter>? chapters,
    AlbumText? ending,
    List<FamilyQuestion>? familyQuestions,
    AlbumNotes? notes,
    MemoryAlbumNarration? narration,
  }) {
    return MemoryAlbum(
      albumId: albumId,
      albumTitle: albumTitle ?? this.albumTitle,
      albumSubtitle: albumSubtitle ?? this.albumSubtitle,
      cover: cover ?? this.cover,
      opening: opening ?? this.opening,
      elderProfileCard: elderProfileCard ?? this.elderProfileCard,
      chapters: chapters ?? this.chapters,
      timeline: timeline,
      ending: ending ?? this.ending,
      familyQuestions: familyQuestions ?? this.familyQuestions,
      notes: notes ?? this.notes,
      narration: narration ?? this.narration,
    );
  }

  Map<String, dynamic> toJson() => {
        'album_id': albumId,
        'album_title': albumTitle,
        'album_subtitle': albumSubtitle,
        'cover': cover.toJson(),
        'opening': opening.toJson(),
        'elder_profile_card': elderProfileCard.toJson(),
        'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
        'timeline': timeline.map((entry) => entry.toJson()).toList(),
        'ending': ending.toJson(),
        'family_questions':
            familyQuestions.map((question) => question.toJson()).toList(),
        'notes': notes.toJson(),
        'narration': narration.toJson(),
      };
}

class MemoryAlbumNarration {
  const MemoryAlbumNarration({
    required this.segments,
  });

  final List<NarrationSegment> segments;

  Map<String, dynamic> toJson() => {
        'segments': segments.map((segment) => segment.toJson()).toList(),
      };
}

class NarrationSegment {
  const NarrationSegment({
    required this.segmentId,
    required this.chapterId,
    required this.chapterTitle,
    required this.itemId,
    required this.itemTitle,
    required this.sentenceIndex,
    required this.text,
    required this.pageIndex,
  });

  final String segmentId;
  final String chapterId;
  final String chapterTitle;
  final String itemId;
  final String itemTitle;
  final int sentenceIndex;
  final String text;
  final int pageIndex;

  Map<String, dynamic> toJson() => {
        'segment_id': segmentId,
        'chapter_id': chapterId,
        'chapter_title': chapterTitle,
        'item_id': itemId,
        'item_title': itemTitle,
        'sentence_index': sentenceIndex,
        'text': text,
        'page_index': pageIndex,
      };
}

class AlbumCover {
  const AlbumCover({
    required this.title,
    required this.subtitle,
    required this.coverText,
    required this.recommendedCoverPhotoId,
  });

  final String title;
  final String subtitle;
  final String coverText;
  final String recommendedCoverPhotoId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'cover_text': coverText,
        'recommended_cover_photo_id': recommendedCoverPhotoId,
      };

  AlbumCover copyWith({
    String? coverText,
  }) {
    return AlbumCover(
      title: title,
      subtitle: subtitle,
      coverText: coverText ?? this.coverText,
      recommendedCoverPhotoId: recommendedCoverPhotoId,
    );
  }
}

class AlbumText {
  const AlbumText({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
      };

  AlbumText copyWith({
    String? content,
  }) {
    return AlbumText(
      title: title,
      content: content ?? this.content,
    );
  }
}

class ElderProfileCard {
  const ElderProfileCard({
    required this.title,
    required this.content,
    required this.profileItems,
  });

  final String title;
  final String content;
  final List<ProfileItem> profileItems;

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'profile_items': profileItems.map((item) => item.toJson()).toList(),
      };

  ElderProfileCard copyWith({
    String? content,
  }) {
    return ElderProfileCard(
      title: title,
      content: content ?? this.content,
      profileItems: profileItems,
    );
  }
}

class ProfileItem {
  const ProfileItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
      };
}

class MemoryAlbumChapter {
  const MemoryAlbumChapter({
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterSubtitle,
    required this.chapterIntro,
    required this.chapterType,
    required this.items,
  });

  final String chapterId;
  final String chapterTitle;
  final String chapterSubtitle;
  final String chapterIntro;
  final String chapterType;
  final List<MemoryAlbumItem> items;

  Map<String, dynamic> toJson() => {
        'chapter_id': chapterId,
        'chapter_title': chapterTitle,
        'chapter_subtitle': chapterSubtitle,
        'chapter_intro': chapterIntro,
        'chapter_type': chapterType,
        'items': items.map((item) => item.toJson()).toList(),
      };

  MemoryAlbumChapter copyWith({
    String? chapterIntro,
    List<MemoryAlbumItem>? items,
  }) {
    return MemoryAlbumChapter(
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      chapterSubtitle: chapterSubtitle,
      chapterIntro: chapterIntro ?? this.chapterIntro,
      chapterType: chapterType,
      items: items ?? this.items,
    );
  }
}

class MemoryAlbumItem {
  const MemoryAlbumItem({
    required this.itemId,
    required this.itemType,
    required this.title,
    required this.content,
    this.photoId = '',
    this.relatedProfileFields = const <String>[],
    this.familyQuestions = const <String>[],
  });

  final String itemId;
  final String itemType;
  final String title;
  final String content;
  final String photoId;
  final List<String> relatedProfileFields;
  final List<String> familyQuestions;

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'item_type': itemType,
        'title': title,
        'content': content,
        'photo_id': photoId,
        'related_profile_fields': relatedProfileFields,
        'family_questions': familyQuestions,
      };

  MemoryAlbumItem copyWith({
    String? content,
    List<String>? familyQuestions,
  }) {
    return MemoryAlbumItem(
      itemId: itemId,
      itemType: itemType,
      title: title,
      content: content ?? this.content,
      photoId: photoId,
      relatedProfileFields: relatedProfileFields,
      familyQuestions: familyQuestions ?? this.familyQuestions,
    );
  }
}

class MemoryTimelineEntry {
  const MemoryTimelineEntry({
    required this.time,
    required this.title,
    required this.content,
    required this.relatedPhotoIds,
  });

  final String time;
  final String title;
  final String content;
  final List<String> relatedPhotoIds;

  Map<String, dynamic> toJson() => {
        'time': time,
        'title': title,
        'content': content,
        'related_photo_ids': relatedPhotoIds,
      };
}

class FamilyQuestion {
  const FamilyQuestion({
    required this.question,
    required this.reason,
  });

  final String question;
  final String reason;

  Map<String, dynamic> toJson() => {
        'question': question,
        'reason': reason,
      };
}

class AlbumNotes {
  const AlbumNotes({
    required this.usedExistingAlbum,
    required this.rewrittenParts,
    required this.addedParts,
    required this.possibleConflicts,
    required this.missingInformation,
  });

  final bool usedExistingAlbum;
  final List<String> rewrittenParts;
  final List<String> addedParts;
  final List<String> possibleConflicts;
  final List<String> missingInformation;

  Map<String, dynamic> toJson() => {
        'used_existing_album': usedExistingAlbum,
        'rewritten_parts': rewrittenParts,
        'added_parts': addedParts,
        'possible_conflicts': possibleConflicts,
        'missing_information': missingInformation,
      };

  AlbumNotes copyWith({
    List<String>? rewrittenParts,
    List<String>? possibleConflicts,
  }) {
    return AlbumNotes(
      usedExistingAlbum: usedExistingAlbum,
      rewrittenParts: rewrittenParts ?? this.rewrittenParts,
      addedParts: addedParts,
      possibleConflicts: possibleConflicts ?? this.possibleConflicts,
      missingInformation: missingInformation,
    );
  }
}
