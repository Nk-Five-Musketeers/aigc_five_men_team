import 'package:flutter_test/flutter_test.dart';

import 'package:aigc_five_men_team/logic/support_card_policy.dart';

void main() {
  group('SupportCardPolicy', () {
    test('ordinary chat does not show cards in the first 6 turns', () {
      for (var turn = 1; turn <= 6; turn++) {
        expect(
          SupportCardPolicy.shouldShowMemoryPrompt(
            latestUserText: '今天天气挺好',
            userTurnCount: turn,
            lastAnyPromptTurn: null,
            lastMemoryPromptTurn: null,
          ),
          isFalse,
        );
        expect(
          SupportCardPolicy.shouldShowCognitivePrompt(
            latestUserText: '今天天气挺好',
            userTurnCount: turn,
            lastAnyPromptTurn: null,
            lastCognitivePromptTurn: null,
          ),
          isFalse,
        );
      }
    });

    test('ordinary chat can show at most one memory prompt on turn 8', () {
      expect(
        SupportCardPolicy.shouldShowMemoryPrompt(
          latestUserText: '今天天气挺好',
          userTurnCount: 8,
          lastAnyPromptTurn: null,
          lastMemoryPromptTurn: null,
        ),
        isTrue,
      );
      expect(
        SupportCardPolicy.shouldShowCognitivePrompt(
          latestUserText: '今天天气挺好',
          userTurnCount: 8,
          lastAnyPromptTurn: null,
          lastCognitivePromptTurn: null,
        ),
        isFalse,
      );
    });

    test('explicit memory intent can show immediately', () {
      expect(
        SupportCardPolicy.shouldShowMemoryPrompt(
          latestUserText: '我想看看以前在老家的照片',
          userTurnCount: 1,
          lastAnyPromptTurn: null,
          lastMemoryPromptTurn: null,
        ),
        isTrue,
      );
    });

    test('repeated explicit memory prompts respect same-type cooldown', () {
      expect(
        SupportCardPolicy.shouldShowMemoryPrompt(
          latestUserText: '我又想起以前上班的事',
          userTurnCount: 3,
          lastAnyPromptTurn: null,
          lastMemoryPromptTurn: 1,
        ),
        isFalse,
      );
      expect(
        SupportCardPolicy.shouldShowMemoryPrompt(
          latestUserText: '我又想起以前上班的事',
          userTurnCount: 4,
          lastAnyPromptTurn: null,
          lastMemoryPromptTurn: 1,
        ),
        isTrue,
      );
    });

    test('cognitive prompt no longer appears every 3 turns', () {
      expect(
        SupportCardPolicy.shouldShowCognitivePrompt(
          latestUserText: '今天下午晒太阳了',
          userTurnCount: 3,
          lastAnyPromptTurn: null,
          lastCognitivePromptTurn: null,
        ),
        isFalse,
      );
      expect(
        SupportCardPolicy.shouldShowCognitivePrompt(
          latestUserText: '今天下午晒太阳了',
          userTurnCount: 12,
          lastAnyPromptTurn: null,
          lastCognitivePromptTurn: null,
        ),
        isTrue,
      );
    });

    test('cognitive prompt skips questions, emotion and memory intent', () {
      for (final text in <String>[
        '今天吃什么呢',
        '我今天很难受',
        '我想起以前上班的事',
      ]) {
        expect(
          SupportCardPolicy.shouldShowCognitivePrompt(
            latestUserText: text,
            userTurnCount: 12,
            lastAnyPromptTurn: null,
            lastCognitivePromptTurn: null,
          ),
          isFalse,
        );
      }
    });

    test('shared cooldown blocks any prompt after a recent card', () {
      expect(
        SupportCardPolicy.shouldShowMemoryPrompt(
          latestUserText: '我想起以前上班的事',
          userTurnCount: 13,
          lastAnyPromptTurn: 8,
          lastMemoryPromptTurn: null,
        ),
        isFalse,
      );
      expect(
        SupportCardPolicy.shouldShowCognitivePrompt(
          latestUserText: '今天下午晒太阳了',
          userTurnCount: 13,
          lastAnyPromptTurn: 8,
          lastCognitivePromptTurn: null,
        ),
        isFalse,
      );
    });
  });
}
