import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:aigc_five_men_team/data/local_db/local_database.dart';

/// cognitive_tests 表 DAO 方法的集成测试。
///
/// 需要在桌面端运行（依赖 sqflite_common_ffi），
/// Web 端使用 IndexedDB 的实现路径可能不同。
///
/// 运行方式：
///   flutter test test/data/local_db/cognitive_tests_dao_test.dart

const _testUserId = 'test_user_cognitive_dao';

void main() {
  // 在所有测试前初始化 FFI（桌面端必须）
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDatabase.ensureUserExists(_testUserId);
  });

  tearDown(() async {
    // 清理测试数据
    final db = await LocalDatabase.instance();
    await db.delete('cognitive_tests',
        where: 'owner_user_id = ?', whereArgs: [_testUserId]);
  });

  group('insertCognitiveTest', () {
    test('插入一条记录并返回 id', () async {
      final id = await LocalDatabase.insertCognitiveTest({
        'owner_user_id': _testUserId,
        'test_type': 'object',
        'image_path': '/photos/apple.jpg',
        'prompt_text': '奶奶您瞅瞅，这是啥呀？',
        'user_answer': '苹果',
        'is_valid': 1,
        'score_note': 'correct',
      });
      expect(id, greaterThan(0));
    });

    test('插入不带可选字段的记录', () async {
      final id = await LocalDatabase.insertCognitiveTest({
        'owner_user_id': _testUserId,
        'test_type': 'scene',
        'is_valid': 0,
      });
      expect(id, greaterThan(0));

      // 验证默认值
      final db = await LocalDatabase.instance();
      final rows = await db.query('cognitive_tests',
          where: 'id = ?', whereArgs: [id]);
      expect(rows, hasLength(1));
      expect(rows.first['score_note'], isNull);
    });
  });

  group('countCognitiveTestsToday', () {
    test('新用户返回 0', () async {
      final count =
          await LocalDatabase.countCognitiveTestsToday(_testUserId);
      expect(count, 0);
    });

    test('插入 3 条后返回 3', () async {
      for (var i = 0; i < 3; i++) {
        await LocalDatabase.insertCognitiveTest({
          'owner_user_id': _testUserId,
          'test_type': 'object',
          'is_valid': 1,
        });
      }
      final count =
          await LocalDatabase.countCognitiveTestsToday(_testUserId);
      expect(count, 3);
    });
  });

  group('getLastCognitiveTestTime', () {
    test('无记录返回 null', () async {
      final t =
          await LocalDatabase.getLastCognitiveTestTime(_testUserId);
      expect(t, isNull);
    });

    test('插入一条后返回非 null 时间', () async {
      await LocalDatabase.insertCognitiveTest({
        'owner_user_id': _testUserId,
        'test_type': 'family',
        'is_valid': 1,
      });
      final t =
          await LocalDatabase.getLastCognitiveTestTime(_testUserId);
      expect(t, isNotNull);
      expect(
        DateTime.now().difference(t!).inSeconds,
        lessThan(10),
      );
    });
  });

  group('getRecentInvalidStreak', () {
    test('无记录返回 0', () async {
      final streak =
          await LocalDatabase.getRecentInvalidStreak(_testUserId);
      expect(streak, 0);
    });

    test('连续 2 条 invalid 返回 2', () async {
      for (var i = 0; i < 2; i++) {
        await LocalDatabase.insertCognitiveTest({
          'owner_user_id': _testUserId,
          'test_type': 'object',
          'is_valid': 0,
          'score_note': 'refuse',
        });
      }
      final streak =
          await LocalDatabase.getRecentInvalidStreak(_testUserId);
      expect(streak, 2);
    });

    test('invalid → valid → invalid 只返回最后 1 条 invalid', () async {
      await LocalDatabase.insertCognitiveTest({
        'owner_user_id': _testUserId,
        'test_type': 'object',
        'is_valid': 0,
        'score_note': 'dontknow',
      });
      await LocalDatabase.insertCognitiveTest({
        'owner_user_id': _testUserId,
        'test_type': 'object',
        'is_valid': 1,
        'score_note': 'correct',
      });
      await LocalDatabase.insertCognitiveTest({
        'owner_user_id': _testUserId,
        'test_type': 'family',
        'is_valid': 0,
        'score_note': 'refuse',
      });
      final streak =
          await LocalDatabase.getRecentInvalidStreak(_testUserId);
      // 从最近一条往回数：第一条(最新) invalid → streak=1, 第二条 valid → break
      expect(streak, 1);
    });

    test('limit 参数控制回溯条数', () async {
      for (var i = 0; i < 4; i++) {
        await LocalDatabase.insertCognitiveTest({
          'owner_user_id': _testUserId,
          'test_type': 'scene',
          'is_valid': 0,
        });
      }
      final streak2 =
          await LocalDatabase.getRecentInvalidStreak(_testUserId, limit: 2);
      expect(streak2, 2);
      final streak3 =
          await LocalDatabase.getRecentInvalidStreak(_testUserId, limit: 3);
      expect(streak3, 3);
    });
  });
}
