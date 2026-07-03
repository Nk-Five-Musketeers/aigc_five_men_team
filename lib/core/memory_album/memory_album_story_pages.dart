import '../../data/models/memory_album.dart';

const String memoryAlbumSubtitle = '慢慢翻，也慢慢听';

class MemoryAlbumStoryPage {
  const MemoryAlbumStoryPage({
    required this.itemId,
    required this.chapterId,
    required this.chapterTitle,
    required this.title,
    required this.body,
    required this.photoId,
  });

  final String itemId;
  final String chapterId;
  final String chapterTitle;
  final String title;
  final String body;
  final String photoId;

  String get narrationText => [
        if (title.trim().isNotEmpty) _ensureSentence(title.trim()),
        body.trim(),
      ].where((part) => part.isNotEmpty).join();
}

List<MemoryAlbumStoryPage> buildMemoryAlbumStoryPages(MemoryAlbum album) {
  const storyChapterTypes = <String>{
    'life_experience',
    'photo_memory',
    'daily_life',
  };
  final pages = <MemoryAlbumStoryPage>[];
  for (final chapter in album.chapters) {
    if (!storyChapterTypes.contains(chapter.chapterType)) continue;
    for (final item in chapter.items) {
      final body = _firstSentences(item.content, 2);
      if (body.isEmpty) continue;
      pages.add(
        MemoryAlbumStoryPage(
          itemId: item.itemId,
          chapterId: chapter.chapterId,
          chapterTitle: chapter.chapterTitle,
          title: item.title.trim(),
          body: body,
          photoId: item.photoId.trim().isNotEmpty
              ? item.photoId
              : album.cover.recommendedCoverPhotoId,
        ),
      );
    }
  }
  return pages;
}

String _firstSentences(String text, int maximum) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  return RegExp(r'[^。！？!?]+[。！？!?]?')
      .allMatches(trimmed)
      .map((match) => match.group(0)?.trim() ?? '')
      .where((sentence) => sentence.isNotEmpty)
      .take(maximum)
      .join();
}

String _ensureSentence(String text) {
  if (text.isEmpty || RegExp(r'[。！？!?]$').hasMatch(text)) return text;
  return '$text。';
}
