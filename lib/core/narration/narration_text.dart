import '../../data/models/memory_album.dart';

List<String> splitNarrationSentences(String text) {
  final source = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (source.isEmpty) return const <String>[];

  final matches = RegExp(r'[^。！？!?；;]+[。！？!?；;]?').allMatches(source);
  final sentences = <String>[];
  for (final match in matches) {
    final sentence = match.group(0)?.trim() ?? '';
    if (sentence.isEmpty) continue;
    sentences.add(sentence);
  }
  return sentences;
}

List<String> splitNarrationBlock({
  required String title,
  required String content,
}) {
  final body = splitNarrationSentences(content);
  final cleanTitle = title.trim();
  if (cleanTitle.length < 4 || body.isEmpty) {
    return body;
  }
  final first = body.first;
  if (first.contains(cleanTitle)) {
    return body;
  }
  return ['$cleanTitle。', ...body];
}

MemoryAlbumNarration buildAlbumNarration(MemoryAlbum album) {
  final segments = <NarrationSegment>[];
  var pageIndex = 0;

  void addBlock({
    required String chapterId,
    required String chapterTitle,
    required String itemId,
    required String itemTitle,
    required String content,
    bool includeTitle = true,
  }) {
    final sentences = includeTitle
        ? splitNarrationBlock(title: itemTitle, content: content)
        : splitNarrationSentences(content);
    for (var i = 0; i < sentences.length; i++) {
      segments.add(
        NarrationSegment(
          segmentId: 'seg_${(segments.length + 1).toString().padLeft(4, '0')}',
          chapterId: chapterId,
          chapterTitle: chapterTitle,
          itemId: itemId,
          itemTitle: itemTitle,
          sentenceIndex: i,
          text: sentences[i],
          pageIndex: pageIndex,
        ),
      );
    }
    pageIndex++;
  }

  addBlock(
    chapterId: 'cover',
    chapterTitle: album.albumTitle,
    itemId: 'cover',
    itemTitle: album.albumTitle,
    content: album.cover.coverText,
  );
  addBlock(
    chapterId: 'opening',
    chapterTitle: album.opening.title,
    itemId: 'opening',
    itemTitle: album.opening.title,
    content: album.opening.content,
  );
  addBlock(
    chapterId: 'profile',
    chapterTitle: album.elderProfileCard.title,
    itemId: 'elder_profile_card',
    itemTitle: album.elderProfileCard.title,
    content: album.elderProfileCard.content,
  );

  for (final chapter in album.chapters) {
    addBlock(
      chapterId: chapter.chapterId,
      chapterTitle: chapter.chapterTitle,
      itemId: '${chapter.chapterId}_intro',
      itemTitle: chapter.chapterTitle,
      content: chapter.chapterIntro,
    );
    for (final item in chapter.items) {
      addBlock(
        chapterId: chapter.chapterId,
        chapterTitle: chapter.chapterTitle,
        itemId: item.itemId,
        itemTitle: item.title,
        content: item.content,
      );
    }
  }

  addBlock(
    chapterId: 'ending',
    chapterTitle: album.ending.title,
    itemId: 'ending',
    itemTitle: album.ending.title,
    content: album.ending.content,
  );

  return MemoryAlbumNarration(segments: segments);
}
