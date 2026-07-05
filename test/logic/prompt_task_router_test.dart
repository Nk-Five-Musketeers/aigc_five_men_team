import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:aigc_five_men_team/data/local_db/local_database.dart';
import 'package:aigc_five_men_team/data/models/chat_message.dart';
import 'package:aigc_five_men_team/logic/prompt_task_router.dart';

/// PromptTaskRouter 纯逻辑单元测试。
///
/// 注意：resolve() 依赖 LocalDatabase（SQLite），需要集成测试环境。
/// 本文件覆盖可脱离 DB 的纯逻辑部分：关键词匹配与问句检测。
/// resolve 的完整场景在集成测试中覆盖。

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDatabase.close();
  });

  // ---------------------------------------------------------------------------
  // 情绪关键词扫描（通过 resolve 的 active_task 返回验证）
  // ---------------------------------------------------------------------------
  group('emotion keyword detection', () {
    test('命中"伤心"返回 emotion_support', () async {
      // 由于 resolve() 依赖 DB, 此处验证纯逻辑: 关键词常量存在且可被匹配
      // 实际触发由路由器的短路逻辑保证 (emotion 优先级最高)
      expect(
        PromptTaskRouter.emotionKeywords.contains('伤心'),
        isTrue,
      );
    });

    test('命中"难受"', () {
      expect(
        PromptTaskRouter.emotionKeywords.contains('难受'),
        isTrue,
      );
    });

    test('命中"孤独"', () {
      expect(
        PromptTaskRouter.emotionKeywords.contains('孤独'),
        isTrue,
      );
    });

    test('命中"睡不着"', () {
      expect(
        PromptTaskRouter.emotionKeywords.contains('睡不着'),
        isTrue,
      );
    });

    test('命中"不想活"', () {
      expect(
        PromptTaskRouter.emotionKeywords.contains('不想活'),
        isTrue,
      );
    });

    test('普通消息不命中', () {
      const normalTexts = <String>[
        '今天天气不错',
        '吃了吗',
        '我想看电视',
        '闺女来电话了',
      ];
      for (final text in normalTexts) {
        final hit = PromptTaskRouter.hasEmotionKeyword(text);
        expect(hit, isFalse, reason: '文本 "$text" 不应命中情绪关键词');
      }
    });

    test('匹配到的关键词以逗号分隔返回', () {
      final hits = PromptTaskRouter.matchedEmotionKeywords('我难受，心里堵得慌');
      expect(hits.contains('难受'), isTrue);
      expect(hits.contains('心里堵'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // 问句检测
  // ---------------------------------------------------------------------------
  group('question detection', () {
    test('以"吗"结尾识别为问句', () {
      expect(PromptTaskRouter.isQuestion('您吃了吗'), isTrue);
    });

    test('以"呢"结尾', () {
      expect(PromptTaskRouter.isQuestion('今天干啥呢'), isTrue);
    });

    test('以"？"结尾', () {
      expect(PromptTaskRouter.isQuestion('这是啥呀？'), isTrue);
    });

    test('以"?"结尾', () {
      expect(PromptTaskRouter.isQuestion('What?'), isTrue);
    });

    test('含"什么"', () {
      expect(PromptTaskRouter.isQuestion('你想说什么'), isTrue);
    });

    test('含"谁"', () {
      expect(PromptTaskRouter.isQuestion('那是谁呀'), isTrue);
    });

    test('含"怎么"', () {
      expect(PromptTaskRouter.isQuestion('怎么走'), isTrue);
    });

    test('含"哪"', () {
      expect(PromptTaskRouter.isQuestion('在哪儿'), isTrue);
    });

    test('含"几"', () {
      expect(PromptTaskRouter.isQuestion('几个人'), isTrue);
    });

    test('陈述句不识别为问句', () {
      const statements = <String>[
        '今天天气不错',
        '我吃过了',
        '挺好的',
        '记不清了',
        '不知道',
      ];
      for (final text in statements) {
        expect(
          PromptTaskRouter.isQuestion(text),
          isFalse,
          reason: '陈述句 "$text" 不应识别为问句',
        );
      }
    });

    test('空文本不识别为问句', () {
      expect(PromptTaskRouter.isQuestion(''), isFalse);
      expect(PromptTaskRouter.isQuestion('   '), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // RouteResult 降级兜底
  // ---------------------------------------------------------------------------
  group('memory intent detection', () {
    test('recognizes explicit memory cues', () {
      for (final text in <String>[
        '我想看看以前的照片',
        '那时候在老家上班',
        '忽然想起来女儿小时候的事',
      ]) {
        expect(PromptTaskRouter.hasMemoryIntent(text), isTrue);
      }
    });

    test('ordinary chat does not count as memory intent', () {
      for (final text in <String>[
        '今天天气挺好',
        '我刚吃完饭',
        '一会儿想看电视',
      ]) {
        expect(PromptTaskRouter.hasMemoryIntent(text), isFalse);
      }
    });
  });

  group('resolve routing', () {
    test('ordinary chat falls back to global only', () async {
      final ownerUserId = await _prepareRouteUser();
      final result = await PromptTaskRouter.resolve(
        userText: '今天天气挺好',
        ownerUserId: ownerUserId,
        recentHistory: [_userMessage('今天天气挺好')],
      );

      expect(result.activeTask, isNull);
      expect(result.memorySnippets, isEmpty);
    });

    test('explicit memory intent routes to memory_chat', () async {
      final ownerUserId = await _prepareRouteUser(withMemory: true);
      final result = await PromptTaskRouter.resolve(
        userText: '我想起以前在老家上班的事',
        ownerUserId: ownerUserId,
        recentHistory: [_userMessage('我想起以前在老家上班的事')],
      );

      expect(result.activeTask, 'memory_chat');
      expect(result.memorySnippets, isNotEmpty);
    });

    test('emotion support still has priority and carries no memory snippets',
        () async {
      final ownerUserId = await _prepareRouteUser(withMemory: true);
      final result = await PromptTaskRouter.resolve(
        userText: '我今天很难受',
        ownerUserId: ownerUserId,
        recentHistory: [_userMessage('我今天很难受')],
      );

      expect(result.activeTask, 'emotion_support');
      expect(result.memorySnippets, isEmpty);
    });
  });

  group('RouteResult', () {
    test('fallback 返回 null activeTask', () {
      final r = RouteResult.fallback();
      expect(r.activeTask, isNull);
      expect(r.taskParams, isEmpty);
    });

    test('fallback 可带 memorySnippets', () {
      final r = RouteResult.fallback(memorySnippets: ['记忆1']);
      expect(r.memorySnippets, ['记忆1']);
    });
  });
}

int _routeUserSeq = 0;

Future<String> _prepareRouteUser({bool withMemory = false}) async {
  final ownerUserId =
      'test_prompt_router_${DateTime.now().microsecondsSinceEpoch}_${_routeUserSeq++}';
  await LocalDatabase.ensureUserExists(ownerUserId);
  await _completeDailyRecord(ownerUserId);
  await _suppressCognitiveRoute(ownerUserId);
  if (withMemory) {
    await LocalDatabase.insertMemoryEvent({
      'owner_user_id': ownerUserId,
      'event_time': '1980年代',
      'title': '老家上班',
      'description': '年轻时候在老家附近上班。',
      'importance': 4,
      'verified': 1,
    });
  }
  return ownerUserId;
}

Future<void> _completeDailyRecord(String ownerUserId) async {
  final today = DateTime.now().toIso8601String().split('T').first;
  await LocalDatabase.upsertDailyLifeRecordByDate({
    'owner_user_id': ownerUserId,
    'date': today,
    'breakfast': '粥',
    'lunch': '面条',
    'dinner': '米饭',
    'activities': '散步',
    'people_met': '家人',
    'places_went': '小区',
    'mood': '平静',
  });
}

Future<void> _suppressCognitiveRoute(String ownerUserId) async {
  for (var i = 0; i < 3; i++) {
    await LocalDatabase.insertCognitiveTest({
      'owner_user_id': ownerUserId,
      'test_type': 'object',
      'is_valid': 1,
    });
  }
}

ChatMessage _userMessage(String content) {
  return ChatMessage(
    id: 'test_msg_${DateTime.now().microsecondsSinceEpoch}',
    content: content,
    isUser: true,
    timestamp: DateTime.now(),
  );
}
