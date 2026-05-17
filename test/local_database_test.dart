import 'package:aigc_five_men_team/data/local_db/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> resetLocalDatabase() async {
    await LocalDatabase.close();
    final path = await LocalDatabase.getDatabasePathForDebug();
    await databaseFactory.deleteDatabase(path);
  }

  setUp(() async {
    await resetLocalDatabase();
  });

  tearDown(() async {
    await resetLocalDatabase();
  });

  test('re-saving a user preserves related nearby people', () async {
    await LocalDatabase.insertUser({
      'id': 'user_1',
      'name': '王阿姨',
      'created_at': '2026-01-01T08:00:00.000',
    });
    await LocalDatabase.upsertNearbyPerson({
      'id': 'nearby_1',
      'owner_user_id': 'user_1',
      'name': '李阿姨',
      'relation': '邻居',
    });

    await LocalDatabase.insertUser({
      'id': 'user_1',
      'name': '王阿姨（更新）',
      'created_at': '2030-01-01T08:00:00.000',
    });

    final user = await LocalDatabase.getUserById('user_1');
    final nearby = await LocalDatabase.getNearbyPeopleForUser('user_1');

    expect(user?['name'], '王阿姨（更新）');
    expect(user?['created_at'], '2026-01-01T08:00:00.000');
    expect(nearby, hasLength(1));
    expect(nearby.single['id'], 'nearby_1');
  });

  test('re-saving a message preserves its attachments', () async {
    await LocalDatabase.insertUser({
      'id': 'user_1',
      'name': '王阿姨',
    });
    await LocalDatabase.createConversation({
      'id': 'conv_1',
      'title': '主会话',
      'owner_user_id': 'user_1',
      'created_at': '2026-01-01T08:00:00.000',
    });
    await LocalDatabase.insertMessage({
      'id': 'msg_1',
      'conversation_id': 'conv_1',
      'user_id': 'user_1',
      'content': '第一版消息',
      'type': 'text',
      'timestamp': '2026-01-01T08:05:00.000',
    });
    await LocalDatabase.insertAttachment({
      'id': 'att_1',
      'message_id': 'msg_1',
      'type': 'image',
      'file_path': 'photo.png',
    });

    await LocalDatabase.insertMessage({
      'id': 'msg_1',
      'conversation_id': 'conv_1',
      'user_id': 'user_1',
      'content': '第二版消息',
      'type': 'text',
      'timestamp': '2026-01-01T08:05:00.000',
    });

    final attachments = await LocalDatabase.getAttachmentsForMessage('msg_1');
    final messages = await LocalDatabase.getMessagesForConversation('conv_1');
    final db = await LocalDatabase.instance();
    final conversations = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: ['conv_1'],
      limit: 1,
    );

    expect(attachments, hasLength(1));
    expect(attachments.single['id'], 'att_1');
    expect(messages, hasLength(1));
    expect(messages.single['content'], '第二版消息');
    expect(conversations.single['last_message_id'], 'msg_1');
  });

  test('nearby person upsert preserves conflict links and normalized lookups',
      () async {
    await LocalDatabase.insertUser({
      'id': 'user_1',
      'name': '王阿姨',
    });
    await LocalDatabase.upsertNearbyPerson({
      'id': 'nearby_1',
      'owner_user_id': 'user_1',
      'name': '李 阿姨',
      'relation': '老 同事',
    });

    final byName =
        await LocalDatabase.findNearbyPersonByNormalizedName('user_1', '李阿姨');
    final byRelation = await LocalDatabase.findNearbyPeopleByNormalizedRelation(
        'user_1', '老同事');

    expect(byName?['id'], 'nearby_1');
    expect(byRelation, hasLength(1));
    expect(byRelation.single['id'], 'nearby_1');

    await LocalDatabase.insertRelationConflict(
      id: 'rc_1',
      ownerUserId: 'user_1',
      personName: '李阿姨',
      fieldName: 'phone',
      nearbyPersonId: 'nearby_1',
      oldValue: '10086',
      newValue: '10010',
    );
    await LocalDatabase.upsertNearbyPerson({
      'id': 'nearby_1',
      'owner_user_id': 'user_1',
      'phone': '10010',
    });

    final conflicts = await LocalDatabase.getPendingRelationConflicts('user_1');
    final updated = await LocalDatabase.getNearbyPersonById('nearby_1');

    expect(conflicts, hasLength(1));
    expect(conflicts.single['nearby_person_id'], 'nearby_1');
    expect(updated?['normalized_name'], '李阿姨');
    expect(updated?['normalized_relation'], '老同事');
    expect(updated?['phone'], '10010');
  });
}
