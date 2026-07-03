import 'dart:convert';

import '../../core/narration/narration_text.dart';
import '../local_db/local_database.dart';
import '../models/memory_album.dart';
import '../models/profile_photo.dart';
import '../models/profile_video.dart';

part 'memory_album_composer.dart';

class MemoryAlbumDraft {
  const MemoryAlbumDraft({
    required this.album,
    required this.photos,
    required this.generationInput,
  });

  final MemoryAlbum album;
  final List<ProfilePhotoModel> photos;
  final Map<String, dynamic> generationInput;

  Map<String, ProfilePhotoModel> get photosById => {
        for (final photo in photos) photo.id: photo,
      };
}

class MemoryAlbumRepository {
  Future<MemoryAlbumDraft> buildForUser(String ownerUserId) async {
    final user = await LocalDatabase.getUserById(ownerUserId);
    final familyMembers =
        await LocalDatabase.listFamilyMembersForUser(ownerUserId);
    final memoryEvents =
        await LocalDatabase.listMemoryEventsForUser(ownerUserId);
    final dailyLifeRecords =
        await LocalDatabase.listDailyLifeRecordsForUser(ownerUserId, limit: 12);
    final photos = await LocalDatabase.listProfilePhotosForUser(ownerUserId);
    final videos = await LocalDatabase.listProfileVideosForUser(ownerUserId);
    final imageOnlyPhotos = photos.where((photo) => !photo.isVideo).toList();
    final allMedia = [...imageOnlyPhotos, ..._photosFromVideos(videos)];

    final generationInput = MemoryAlbumComposer.buildGenerationInput(
      ownerUserId: ownerUserId,
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: allMedia,
    );
    final album = MemoryAlbumComposer.compose(
      ownerUserId: ownerUserId,
      user: user,
      familyMembers: familyMembers,
      memoryEvents: memoryEvents,
      dailyLifeRecords: dailyLifeRecords,
      photos: allMedia,
    );

    return MemoryAlbumDraft(
      album: album,
      photos: allMedia,
      generationInput: generationInput,
    );
  }

  static List<ProfilePhotoModel> _photosFromVideos(
    List<ProfileVideoModel> videos,
  ) {
    return videos
        .map(
          (video) => ProfilePhotoModel(
            id: video.id,
            ownerUserId: video.ownerUserId,
            filePath: video.filePath,
            category: ProfilePhotoCategory.memory,
            caption: video.caption,
            metadata: {
              'source': 'chat',
              'media_type': 'video',
              'message_id': video.messageId,
            },
            createdAt: video.createdAt,
          ),
        )
        .toList();
  }
}
