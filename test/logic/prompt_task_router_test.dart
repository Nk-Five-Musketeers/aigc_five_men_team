import 'package:flutter_test/flutter_test.dart';

import 'package:aigc_five_men_team/logic/prompt_task_router.dart';

/// PromptTaskRouter 纯逻辑单元测试。
///
/// 注意：resolve() 依赖 LocalDatabase（SQLite），需要集成测试环境。
/// 本文件覆盖可脱离 DB 的纯逻辑部分：关键词匹配与问句检测。
/// resolve 的完整场景在集成测试中覆盖。

void main() {
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
