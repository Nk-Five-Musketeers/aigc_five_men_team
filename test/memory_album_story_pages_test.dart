import 'package:aigc_five_men_team/core/memory_album/memory_album_story_pages.dart';
import 'package:aigc_five_men_team/data/models/memory_album.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildMemoryAlbumStoryPages keeps story chapters and trims body', () {
    final pages = buildMemoryAlbumStoryPages(_album());

    expect(pages.map((page) => page.itemId), [
      'life_1',
      'photo_1',
      'daily_1',
    ]);
    expect(pages.first.body, '第一句。第二句！');
    expect(pages.first.photoId, 'cover_photo');
    expect(pages[1].photoId, 'photo_1');
  });

  test('album subtitle is stable and reader friendly', () {
    expect(memoryAlbumSubtitle, '慢慢翻，也慢慢听');
  });
}

MemoryAlbum _album() {
  return const MemoryAlbum(
    albumId: 'album_1',
    albumTitle: '于小晨的回忆图鉴',
    albumSubtitle: '旧副标题',
    cover: AlbumCover(
      title: '于小晨',
      subtitle: '旧封面副标题',
      coverText: '旧封面介绍',
      recommendedCoverPhotoId: 'cover_photo',
    ),
    opening: AlbumText(title: '慢慢翻', content: '打开影集。'),
    elderProfileCard: ElderProfileCard(
      title: '关于于小晨',
      content: '档案正文',
      profileItems: [],
    ),
    chapters: [
      MemoryAlbumChapter(
        chapterId: 'profile',
        chapterTitle: '一个人的轮廓',
        chapterSubtitle: '',
        chapterIntro: '',
        chapterType: 'profile',
        items: [
          MemoryAlbumItem(
            itemId: 'profile_1',
            itemType: 'text_card',
            title: '档案',
            content: '不应进入单页影集。',
          ),
        ],
      ),
      MemoryAlbumChapter(
        chapterId: 'life',
        chapterTitle: '走过的日子',
        chapterSubtitle: '',
        chapterIntro: '',
        chapterType: 'life_experience',
        items: [
          MemoryAlbumItem(
            itemId: 'life_1',
            itemType: 'timeline_card',
            title: '一段经历',
            content: '第一句。第二句！第三句？',
          ),
        ],
      ),
      MemoryAlbumChapter(
        chapterId: 'photo',
        chapterTitle: '照片里的那一刻',
        chapterSubtitle: '',
        chapterIntro: '',
        chapterType: 'photo_memory',
        items: [
          MemoryAlbumItem(
            itemId: 'photo_1',
            itemType: 'photo_card',
            title: '一张照片',
            content: '照片中的故事。',
            photoId: 'photo_1',
          ),
        ],
      ),
      MemoryAlbumChapter(
        chapterId: 'daily',
        chapterTitle: '日常里的安稳',
        chapterSubtitle: '',
        chapterIntro: '',
        chapterType: 'daily_life',
        items: [
          MemoryAlbumItem(
            itemId: 'daily_1',
            itemType: 'text_card',
            title: '一天',
            content: '平常的一天。',
          ),
        ],
      ),
    ],
    timeline: [],
    ending: AlbumText(title: '继续', content: '故事继续。'),
    familyQuestions: [],
    notes: AlbumNotes(
      usedExistingAlbum: false,
      rewrittenParts: [],
      addedParts: [],
      possibleConflicts: [],
      missingInformation: [],
    ),
    narration: MemoryAlbumNarration(segments: []),
  );
}
