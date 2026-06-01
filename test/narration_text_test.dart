import 'package:flutter_test/flutter_test.dart';
import 'package:aigc_five_men_team/core/narration/narration_text.dart';
import 'package:aigc_five_men_team/data/models/memory_album.dart';

void main() {
  test('splitNarrationSentences keeps Chinese punctuation', () {
    expect(
      splitNarrationSentences(
        '午后的亭子里，阳光落在身旁。于小晨坐在那里，手边放着常用的保温杯。这样的画面不张扬，却让人觉得安心。',
      ),
      [
        '午后的亭子里，阳光落在身旁。',
        '于小晨坐在那里，手边放着常用的保温杯。',
        '这样的画面不张扬，却让人觉得安心。',
      ],
    );
  });

  test('splitNarrationBlock skips short titles and includes useful titles', () {
    expect(
      splitNarrationBlock(title: '慢慢翻', content: '今天先从照片说起。'),
      ['今天先从照片说起。'],
    );
    expect(
      splitNarrationBlock(title: '亭子里的午后', content: '阳光落在身旁。'),
      ['亭子里的午后。', '阳光落在身旁。'],
    );
  });

  test('splitNarrationSentences softly splits overly long comma sentences', () {
    final sentences = splitNarrationSentences(
      '我们记得，你曾经站在讲台上，把许多知识慢慢讲给别人听，也把认真生活的样子留在家里人的记忆里，那些日子后来被我们反复想起。',
    );

    expect(sentences.length, greaterThan(1));
    expect(sentences.every((sentence) => sentence.endsWith('。')), isTrue);
    expect(sentences.join(), contains('讲台上'));
    expect(sentences.join(), contains('反复想起'));
  });

  test('buildAlbumNarration creates ordered segments for album pages', () {
    const album = MemoryAlbum(
      albumId: 'album_001',
      albumTitle: '于小晨的回忆图鉴',
      albumSubtitle: '有我在，记忆不孤单',
      cover: AlbumCover(
        title: '于小晨',
        subtitle: '天津',
        coverText: '于小晨的故事，藏在家人记得的一件件小事里。',
        recommendedCoverPhotoId: 'photo_001',
      ),
      opening: AlbumText(
        title: '慢慢翻',
        content: '这是于小晨的回忆，也是家人一起记住的日子。',
      ),
      elderProfileCard: ElderProfileCard(
        title: '关于于小晨',
        content: '于小晨和天津有着熟悉的来处。',
        profileItems: [ProfileItem(label: '姓名', value: '于小晨')],
      ),
      chapters: [
        MemoryAlbumChapter(
          chapterId: 'chapter_001',
          chapterTitle: '亭子里的午后',
          chapterSubtitle: '照片里的故事入口',
          chapterIntro: '照片留下了于小晨生命里的一个片刻。',
          chapterType: 'photo_memory',
          items: [
            MemoryAlbumItem(
              itemId: 'item_001',
              itemType: 'photo_card',
              title: '亭子里的午后',
              content: '午后的亭子里，阳光落在身旁。这样的画面让人安心。',
              photoId: 'photo_001',
            ),
          ],
        ),
      ],
      timeline: [],
      ending: AlbumText(title: '故事还在继续', content: '于小晨的日子还在继续，家人的记挂也还在继续。'),
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

    final narration = buildAlbumNarration(album);

    expect(narration.segments, isNotEmpty);
    expect(narration.segments.first.itemId, 'cover');
    expect(narration.segments.first.text, '于小晨的回忆图鉴。');
    expect(
      narration.segments.map((segment) => segment.text),
      contains('午后的亭子里，阳光落在身旁。'),
    );
    expect(
      narration.segments.map((segment) => segment.pageIndex).toSet().length,
      greaterThan(1),
    );
  });
}
