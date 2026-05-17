import 'package:flutter_test/flutter_test.dart';
import 'package:aigc_five_men_team/data/models/profile_photo.dart';

void main() {
  test('profile photo enums use database values', () {
    expect(ProfilePhotoStorageType.fromValue('file_path'),
        ProfilePhotoStorageType.filePath);
    expect(ProfilePhotoStorageType.fromValue('web_local'),
        ProfilePhotoStorageType.webLocal);
    expect(
        ProfilePhotoCategory.fromValue('memory'), ProfilePhotoCategory.memory);
    expect(ProfilePhotoCategory.fromValue('unexpected'),
        ProfilePhotoCategory.other);
  });
}
