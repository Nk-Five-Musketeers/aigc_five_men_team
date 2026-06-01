part of '../home_screen.dart';

class _AlbumCoverPanel extends StatelessWidget {
  const _AlbumCoverPanel({
    required this.album,
    required this.photo,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final MemoryAlbum album;
  final ProfilePhotoModel? photo;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    return _AlbumPanel(
      key: keyForItem('cover'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: SizedBox(
                height: 210,
                child: _MemoryPhotoImage(photo: photo!),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _NarrationTitle(
            text: album.albumTitle,
            entry: _titleEntryForItem(
              narrationPlayer,
              'cover',
              album.albumTitle,
            ),
            state: narrationPlayer.state,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.text,
              height: 1.15,
            ),
          ),
          if (album.albumSubtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              album.albumSubtitle,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w500,
                color: AppTheme.primaryDeep,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _NarrationTextBlock(
            itemId: 'cover',
            title: album.albumTitle,
            fallbackText: album.cover.coverText,
            narrationPlayer: narrationPlayer,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            textStyle: const TextStyle(
              fontSize: 20,
              height: 1.45,
              color: AppTheme.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumTextPanel extends StatelessWidget {
  const _AlbumTextPanel({
    required this.text,
    required this.itemId,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final AlbumText text;
  final String itemId;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    if (text.content.trim().isEmpty) return const SizedBox.shrink();
    return _AlbumPanel(
      key: keyForItem(itemId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NarrationTitle(
            text: text.title,
            entry: _titleEntryForItem(narrationPlayer, itemId, text.title),
            state: narrationPlayer.state,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            style: _AlbumSectionTitle.style,
          ),
          const SizedBox(height: 8),
          _NarrationTextBlock(
            itemId: itemId,
            title: text.title,
            fallbackText: text.content,
            narrationPlayer: narrationPlayer,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            textStyle: const TextStyle(
              fontSize: 20,
              height: 1.48,
              color: AppTheme.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumProfilePanel extends StatelessWidget {
  const _AlbumProfilePanel({
    required this.card,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final ElderProfileCard card;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    if (card.profileItems.isEmpty) return const SizedBox.shrink();
    return _AlbumPanel(
      key: keyForItem('elder_profile_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NarrationTitle(
            text: card.title,
            entry: _titleEntryForItem(
              narrationPlayer,
              'elder_profile_card',
              card.title,
            ),
            state: narrationPlayer.state,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            style: _AlbumSectionTitle.style,
          ),
          const SizedBox(height: 8),
          _NarrationTextBlock(
            itemId: 'elder_profile_card',
            title: card.title,
            fallbackText: card.content,
            narrationPlayer: narrationPlayer,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            textStyle: const TextStyle(
              fontSize: 20,
              height: 1.45,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in card.profileItems)
                _AlbumInfoPill(label: item.label, value: item.value),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlbumChapterPanel extends StatelessWidget {
  const _AlbumChapterPanel({
    required this.chapter,
    required this.photosById,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final MemoryAlbumChapter chapter;
  final Map<String, ProfilePhotoModel> photosById;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    if (chapter.items.isEmpty) return const SizedBox.shrink();
    final introItemId = '${chapter.chapterId}_intro';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            key: keyForItem(introItemId),
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NarrationTitle(
                  text: chapter.chapterTitle,
                  entry: _titleEntryForItem(
                    narrationPlayer,
                    introItemId,
                    chapter.chapterTitle,
                  ),
                  state: narrationPlayer.state,
                  keyForSegment: keyForSegment,
                  onSegmentTap: onSegmentTap,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text,
                    height: 1.2,
                  ),
                ),
                if (chapter.chapterSubtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    chapter.chapterSubtitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSoft,
                    ),
                  ),
                ],
                if (chapter.chapterIntro.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _NarrationTextBlock(
                    itemId: introItemId,
                    title: chapter.chapterTitle,
                    fallbackText: chapter.chapterIntro,
                    narrationPlayer: narrationPlayer,
                    keyForSegment: keyForSegment,
                    onSegmentTap: onSegmentTap,
                    textStyle: const TextStyle(
                      fontSize: 19,
                      height: 1.4,
                      color: AppTheme.text,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final item in chapter.items)
            _AlbumItemPanel(
              item: item,
              photo: photosById[item.photoId],
              narrationPlayer: narrationPlayer,
              keyForSegment: keyForSegment,
              keyForItem: keyForItem,
              onSegmentTap: onSegmentTap,
            ),
        ],
      ),
    );
  }
}

class _AlbumItemPanel extends StatelessWidget {
  const _AlbumItemPanel({
    required this.item,
    required this.photo,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final MemoryAlbumItem item;
  final ProfilePhotoModel? photo;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    return _AlbumPanel(
      key: keyForItem(item.itemId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: SizedBox(
                height: 190,
                child: _MemoryPhotoImage(photo: photo!),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AlbumTypeBadge(type: item.itemType),
              const SizedBox(width: 8),
              Expanded(
                child: _NarrationTitle(
                  text: item.title,
                  entry: _titleEntryForItem(
                    narrationPlayer,
                    item.itemId,
                    item.title,
                  ),
                  state: narrationPlayer.state,
                  keyForSegment: keyForSegment,
                  onSegmentTap: onSegmentTap,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _NarrationTextBlock(
            itemId: item.itemId,
            title: item.title,
            fallbackText: item.content,
            narrationPlayer: narrationPlayer,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            textStyle: const TextStyle(
              fontSize: 20,
              height: 1.5,
              color: AppTheme.text,
            ),
          ),
          if (item.familyQuestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final question in item.familyQuestions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      size: 18,
                      color: AppTheme.primaryDeep,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        question,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.35,
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AlbumTimelinePanel extends StatelessWidget {
  const _AlbumTimelinePanel({required this.entries});

  final List<MemoryTimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return _AlbumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AlbumSectionTitle('时间线'),
          const SizedBox(height: 8),
          for (final entry in entries.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 82,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                    child: Text(
                      entry.time.isEmpty ? '待补' : entry.time,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.text,
                          ),
                        ),
                        if (entry.content.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              entry.content,
                              style: const TextStyle(
                                fontSize: 18,
                                height: 1.4,
                                color: AppTheme.textSoft,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AlbumQuestionsPanel extends StatelessWidget {
  const _AlbumQuestionsPanel({required this.questions});

  final List<FamilyQuestion> questions;

  @override
  Widget build(BuildContext context) {
    return _AlbumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AlbumSectionTitle('可以再问问家里人'),
          const SizedBox(height: 8),
          for (final question in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.question,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                    ),
                  ),
                  if (question.reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        question.reason,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.35,
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AlbumNotesPanel extends StatelessWidget {
  const _AlbumNotesPanel({required this.notes});

  final AlbumNotes notes;

  @override
  Widget build(BuildContext context) {
    if (notes.missingInformation.isEmpty && notes.addedParts.isEmpty) {
      return const SizedBox.shrink();
    }
    return _AlbumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AlbumSectionTitle('还可以慢慢补'),
          const SizedBox(height: 8),
          if (notes.addedParts.isNotEmpty)
            Text(
              '现在已经写下：${notes.addedParts.join('、')}',
              style: const TextStyle(
                fontSize: 18,
                height: 1.4,
                color: AppTheme.textSoft,
              ),
            ),
          if (notes.missingInformation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '以后还可以补：${notes.missingInformation.join('、')}',
              style: const TextStyle(
                fontSize: 18,
                height: 1.4,
                color: AppTheme.textSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumPanel extends StatelessWidget {
  const _AlbumPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: child,
    );
  }
}

class _AlbumSectionTitle extends StatelessWidget {
  const _AlbumSectionTitle(this.text);

  final String text;

  static const style = TextStyle(
    fontSize: 23,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppTheme.text,
  );

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
    );
  }
}

class _AlbumInfoPill extends StatelessWidget {
  const _AlbumInfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Text(
        '$label：$value',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppTheme.text,
        ),
      ),
    );
  }
}

class _AlbumTypeBadge extends StatelessWidget {
  const _AlbumTypeBadge({required this.type});

  final String type;

  String get _label {
    return switch (type) {
      'photo_card' => '照片',
      'profile_card' => '人物',
      'timeline_card' => '经历',
      'quote_card' => '话语',
      'question_card' => '问题',
      _ => '文字',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
