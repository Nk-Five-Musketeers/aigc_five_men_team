import 'prompt_task_router.dart';

class SupportCardPolicy {
  SupportCardPolicy._();

  static const int sharedCooldownTurns = 6;
  static const int explicitMemoryCooldownTurns = 3;
  static const int ambientMemoryIntervalTurns = 8;
  static const int cognitiveIntervalTurns = 12;
  static const int _neverShownTurns = 1 << 20;

  static bool shouldShowMemoryPrompt({
    required String latestUserText,
    required int userTurnCount,
    required int? lastAnyPromptTurn,
    required int? lastMemoryPromptTurn,
    bool allowAmbient = true,
  }) {
    final hasMemoryIntent = PromptTaskRouter.hasMemoryIntent(latestUserText);
    if (!hasMemoryIntent && !allowAmbient) return false;
    if (!_sharedCooldownReady(userTurnCount, lastAnyPromptTurn)) return false;

    final turnsSinceMemory = _turnsSince(userTurnCount, lastMemoryPromptTurn);
    if (hasMemoryIntent) {
      return turnsSinceMemory >= explicitMemoryCooldownTurns;
    }

    return userTurnCount >= ambientMemoryIntervalTurns &&
        turnsSinceMemory >= ambientMemoryIntervalTurns;
  }

  static bool shouldShowCognitivePrompt({
    required String latestUserText,
    required int userTurnCount,
    required int? lastAnyPromptTurn,
    required int? lastCognitivePromptTurn,
  }) {
    if (PromptTaskRouter.hasMemoryIntent(latestUserText)) return false;
    if (PromptTaskRouter.hasEmotionKeyword(latestUserText)) return false;
    if (PromptTaskRouter.isQuestion(latestUserText)) return false;
    if (!_sharedCooldownReady(userTurnCount, lastAnyPromptTurn)) return false;

    return userTurnCount >= cognitiveIntervalTurns &&
        _turnsSince(userTurnCount, lastCognitivePromptTurn) >=
            cognitiveIntervalTurns;
  }

  static bool _sharedCooldownReady(int userTurnCount, int? lastAnyPromptTurn) {
    return _turnsSince(userTurnCount, lastAnyPromptTurn) >= sharedCooldownTurns;
  }

  static int _turnsSince(int userTurnCount, int? lastTurn) {
    if (lastTurn == null) return _neverShownTurns;
    return userTurnCount - lastTurn;
  }
}
