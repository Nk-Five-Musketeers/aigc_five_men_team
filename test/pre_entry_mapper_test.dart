import 'package:flutter_test/flutter_test.dart';
import 'package:aigc_five_men_team/data/repositories/pre_entry_mapper.dart';

void main() {
  test('buildFamilyMemberPatchFromNearby keeps completed questionnaire fields',
      () {
    final patch = PreEntryMapper.buildFamilyMemberPatchFromNearby({
      'owner_user_id': 'elder_1',
      'name': '李明',
      'relation': '儿子',
      'photo_path': r'D:\app-data\son.jpg',
      'birthday': '1978-06-01',
      'location': '上海',
      'address': '上海市浦东新区',
      'contact_freq': '每周电话',
      'note': '老人常叫他小明，周末会来探望',
      'is_active': 1,
    });

    expect(patch['owner_user_id'], 'elder_1');
    expect(patch['name'], '李明');
    expect(patch['relation'], '儿子');
    expect(patch['photo_path'], r'D:\app-data\son.jpg');
    expect(patch['birthday'], '1978-06-01');
    expect(patch['location'], '上海');
    expect(patch['contact_freq'], '每周电话');
    expect(patch['notes'], '老人常叫他小明，周末会来探望');
    expect(patch['is_active'], 1);
  });

  test('buildFamilyMemberPatchFromNearby falls back to address for location',
      () {
    final patch = PreEntryMapper.buildFamilyMemberPatchFromNearby({
      'owner_user_id': 'elder_1',
      'name': '王芳',
      'relation': '女儿',
      'address': '成都市青羊区',
      'note': '每天晚饭后打电话',
    });

    expect(patch['location'], '成都市青羊区');
    expect(patch['notes'], '每天晚饭后打电话');
    expect(patch['is_active'], 1);
  });
}
