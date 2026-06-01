import '../../data/models/memory_album.dart';

List<String> splitNarrationSentences(String text) {
  final source = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (source.isEmpty) return const <String>[];

  final matches = RegExp(r'[^。！？!?；;]+[。！？!?；;]?').allMatches(source);
  final sentences = <String>[];
  for (final match in matches) {
    final sentence = match.group(0)?.trim() ?? '';
    if (sentence.isEmpty) continue;
    sentences.addAll(_splitLongNarrationSentence(sentence));
  }
  return sentences;
}

List<String> _splitLongNarrationSentence(String sentence) {
  const maxLength = 46;
  const minPartLength = 14;
  final trimmed = sentence.trim();
  if (trimmed.length <= maxLength) return [trimmed];

  final sentenceEnd = RegExp(r'[。！？!?；;]$').firstMatch(trimmed)?.group(0);
  final body = sentenceEnd == null
      ? trimmed
      : trimmed.substring(0, trimmed.length - sentenceEnd.length);
  final commaMatches = RegExp(r'[^，,、]+[，,、]?').allMatches(body);
  final commaParts = commaMatches
      .map((match) => match.group(0)?.trim() ?? '')
      .where((part) => part.isNotEmpty)
      .toList();
  if (commaParts.length < 2) return [trimmed];

  final chunks = <String>[];
  var current = '';
  for (final part in commaParts) {
    final candidate = current + part;
    if (current.isNotEmpty &&
        candidate.length > maxLength &&
        current.length >= minPartLength) {
      chunks.add(_ensureNarrationPunctuation(current));
      current = part;
    } else {
      current = candidate;
    }
  }
  if (current.isNotEmpty) {
    chunks.add(_ensureNarrationPunctuation(current, fallback: sentenceEnd));
  }

  if (chunks.length < 2 ||
      chunks.any((chunk) => chunk.length < minPartLength)) {
    return [trimmed];
  }
  return chunks;
}

String _ensureNarrationPunctuation(String value, {String? fallback}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (RegExp(r'[。！？!?；;]$').hasMatch(trimmed)) return trimmed;
  return '$trimmed${fallback ?? '。'}';
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
