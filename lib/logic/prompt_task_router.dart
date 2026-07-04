import '../data/local_db/local_database.dart';
import '../data/models/chat_message.dart';

/// 路由决策结果。
class RouteResult {
  final String? activeTask;
  final Map<String, dynamic> taskParams;
  final List<String> memorySnippets;

  const RouteResult({
    this.activeTask,
    this.taskParams = const <String, dynamic>{},
    this.memorySnippets = const <String>[],
  });

  /// 降级兜底：仅 global，无任务模块。
  factory RouteResult.fallback({List<String>? memorySnippets}) {
    return RouteResult(
      activeTask: null,
      memorySnippets: memorySnippets ?? const <String>[],
    );
  }
}

/// 决定 active_task 与 task_params，纯本地 + 同步逻辑（SQL 查询除外）。
///
/// 判定顺序（短路）：
/// 1. emotion_support — 用户文本命中情绪关键词
/// 2. daily_greeting — 当日 daily_life_records 有缺口 且 今日首次用户消息
/// 3. cognitive_test — 频控通过 + 话题空档
/// 4. memory_chat — 默认兜底
class PromptTaskRouter {
  PromptTaskRouter._();

  // ---------------------------------------------------------------------------
  // 情绪关键词（约 30 条，按情绪强度大致排序）
  // ---------------------------------------------------------------------------
  /// 情绪关键词列表（便于审阅与测试）。
  static const List<String> emotionKeywords = <String>[
    '伤心',
    '难受',
    '想他',
    '想她',
    '没意思',
    '孤独',
    '一个人',
    '睡不着',
    '疼',
    '难过',
    '哭了',
    '不想活',
    '没用',
    '累极了',
    '烦死了',
    '害怕',
    '担心',
    '不高兴',
    '不开心',
    '闷得慌',
    '心里堵',
    '没劲',
    '活够了',
    '受够了',
    '憋屈',
    '委屈',
    '心慌',
    '发愁',
    '不痛快',
    '堵心',
  ];

  // ---------------------------------------------------------------------------
  // 中文问句检测（粗略，不追求完美）
  // ---------------------------------------------------------------------------
  static const List<String> questionMarkers = <String>[
    '?',
    '？',
    '吗',
    '呢',
    '什么',
    '啥',
    '谁',
    '哪',
    '怎么',
    '咋',
    '几',
    '多少',
    '要不要',
    '能不能',
    '行不行',
    '好不好',
    '对不对',
    '可不可以',
    '是不是',
    '有没有',
    '在哪',
    '干嘛',
    '干啥',
  ];

  /// 粗略检测中文问句（不追求完美）。
  static bool isQuestion(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    if (t.endsWith('?') || t.endsWith('？')) return true;
    for (final m in questionMarkers) {
      if (t.contains(m)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // 情绪关键词扫描
  // ---------------------------------------------------------------------------
  /// 检测文本是否命中任意情绪关键词。
  static bool hasEmotionKeyword(String text) {
    for (final kw in emotionKeywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// 返回命中的全部情绪关键词。
  static List<String> matchedEmotionKeywords(String text) {
    final hits = <String>[];
    for (final kw in emotionKeywords) {
      if (text.contains(kw)) hits.add(kw);
    }
    return hits;
  }

  static const List<String> memoryIntentKeywords = <String>[
    '以前',
    '从前',
    '过去',
    '年轻时候',
    '年轻时',
    '小时候',
    '那时候',
    '那会儿',
    '老家',
    '上班',
    '工作那会儿',
    '照片',
    '相片',
    '家人',
    '家里人',
    '女儿',
    '儿子',
    '老伴',
    '孙子',
    '孙女',
    '记得',
    '想起来',
    '想起',
    '回忆',
    '往事',
  ];

  static bool hasMemoryIntent(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    for (final kw in memoryIntentKeywords) {
      if (t.contains(kw)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // 主入口
  // ---------------------------------------------------------------------------

  /// 决定 active_task 并构造 task_params。
  /// 任何步骤失败都 fall back 到 memory_chat，不抛异常。
  static Future<RouteResult> resolve({
    required String userText,
    required String ownerUserId,
    required List<ChatMessage> recentHistory,
  }) async {
    try {
      // 1) emotion_support — 最高优先级，短路
      if (hasEmotionKeyword(userText)) {
        return RouteResult(
          activeTask: 'emotion_support',
          taskParams: await _buildEmotionParams(userText, ownerUserId),
        );
      }

      // 2) daily_greeting
      final greeting =
          await _tryDailyGreeting(ownerUserId, userText, recentHistory);
      if (greeting != null) {
        return RouteResult(
          activeTask: 'daily_greeting',
          taskParams: greeting,
        );
      }

      // 3) cognitive_test
      final cognitive =
          await _tryCognitiveTest(ownerUserId, userText, recentHistory);
      if (cognitive != null) {
        return RouteResult(
          activeTask: 'cognitive_test',
          taskParams: cognitive,
        );
      }

      // 4) memory_chat — 仅在明确记忆意图时触发
      if (hasMemoryIntent(userText)) {
        final memorySnippets = await _buildMemorySnippets(ownerUserId);
        return RouteResult(
          activeTask: 'memory_chat',
          taskParams: _buildMemoryChatParams(userText, memorySnippets),
          memorySnippets: memorySnippets,
        );
      }

      return const RouteResult();
    } catch (_) {
      return RouteResult.fallback();
    }
  }

  // ---------------------------------------------------------------------------
  // 各任务参数构造
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _buildEmotionParams(
    String userText,
    String ownerUserId,
  ) async {
    final positiveTopics = await _queryPositiveMemories(ownerUserId);
    return <String, dynamic>{
      'emotion_type': 'sad',
      'trigger_content': userText,
      'trigger_keywords': matchedEmotionKeywords(userText),
      'positive_topics': positiveTopics,
    };
  }

  /// 从 memory_events 查正向情绪记忆，供情绪安抚时引导转暖话题。
  static Future<List<String>> _queryPositiveMemories(String ownerUserId) async {
    try {
      final db = await LocalDatabase.instance();
      final rows = await db.rawQuery(
        'SELECT title, description FROM memory_events '
        'WHERE owner_user_id = ? AND (emotion IN (?,?,?) OR importance >= 4) '
        'ORDER BY importance DESC LIMIT 4',
        [ownerUserId, '开心', '喜悦', '满足'],
      );
      final snippets = <String>[];
      for (final r in rows) {
        final parts = <String>[];
        final t = r['title'] as String?;
        final d = r['description'] as String?;
        if (t != null && t.isNotEmpty) parts.add(t);
        if (d != null && d.isNotEmpty) parts.add(d);
        if (parts.isNotEmpty) snippets.add(parts.join('：'));
      }
      return snippets;
    } catch (_) {
      return <String>[];
    }
  }

  static Map<String, dynamic> _buildMemoryChatParams(
    String userText,
    List<String> snippets,
  ) {
    return <String, dynamic>{
      'conversation_context':
          userText.length > 60 ? '${userText.substring(0, 60)}…' : userText,
    };
  }

  // ---------------------------------------------------------------------------
  // daily_greeting 判定
  // ---------------------------------------------------------------------------

  /// 返回 task_params 或 null（不触发）。
  static Future<Map<String, dynamic>?> _tryDailyGreeting(
    String ownerUserId,
    String userText,
    List<ChatMessage> recentHistory,
  ) async {
    try {
      // 条件 1: 当日 daily_life_records 不存在 或 存在但至少 1 个字段为空
      final today = DateTime.now().toIso8601String().split('T').first;
      final record = await LocalDatabase.getDailyLifeRecordByUserAndDate(
          ownerUserId, today);

      const allFields = <String>[
        'breakfast',
        'lunch',
        'dinner',
        'activities',
        'people_met',
        'places_went',
        'mood',
      ];

      List<String> missingFields;
      if (record == null) {
        missingFields = List<String>.from(allFields);
      } else {
        missingFields = <String>[];
        for (final f in allFields) {
          final v = (record[f] as String?)?.trim();
          if (v == null || v.isEmpty) {
            missingFields.add(f);
          }
        }
      }

      if (missingFields.isEmpty) return null; // 今日已全部填完

      // 条件 2: 历史最近 6 条消息中无情绪关键词
      final recent6 = recentHistory.reversed.take(6).toList();
      for (final m in recent6) {
        if (m.isUser && hasEmotionKeyword(m.content)) {
          return null;
        }
      }

      // 条件 3: 本次是当日首条 user 消息
      // 注意：调用方在 _buildPromptContextAsync 前已将当前消息写入 messages 表，
      // 因此当日首条时 DB 计数为 1（仅当前消息），用 <= 1 兼容保存失败仍为 0 的情况。
      final todayMsgCount =
          await LocalDatabase.countMessagesTodayByUser(ownerUserId, today);
      if (todayMsgCount > 1) return null;

      return <String, dynamic>{
        'missing_fields': missingFields,
        'today': today,
        'elder_name': '奶奶',
      };
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // cognitive_test 判定
  // ---------------------------------------------------------------------------

  /// 返回 task_params 或 null（不触发）。
  static Future<Map<String, dynamic>?> _tryCognitiveTest(
    String ownerUserId,
    String userText,
    List<ChatMessage> recentHistory,
  ) async {
    try {
      // 条件 1: 用户当前文本不是问句（不打断老人提问）
      if (hasMemoryIntent(userText)) return null;
      if (isQuestion(userText)) return null;

      // 条件 2: 用户上一条回复非问句 且 长度 ≥ 4 字（话题空档判定）
      final lastUserMsg = recentHistory.reversed.firstWhere(
        (m) => m.isUser,
        orElse: () => ChatMessage(
          id: '',
          content: '',
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      if (lastUserMsg.content.isEmpty) return null;
      if (isQuestion(lastUserMsg.content)) return null;
      if (lastUserMsg.content.trim().length < 4) return null;

      // 条件 3: 频控 — 今日次数 < 3
      final todayCount =
          await LocalDatabase.countCognitiveTestsToday(ownerUserId);
      if (todayCount >= 3) return null;

      // 条件 4: 距上次 ≥ 1 小时
      final lastTime =
          await LocalDatabase.getLastCognitiveTestTime(ownerUserId);
      if (lastTime != null) {
        final elapsed = DateTime.now().difference(lastTime);
        if (elapsed.inMinutes < 60) return null;
      }

      // 条件 5: 连续无效 < 2
      final invalidStreak =
          await LocalDatabase.getRecentInvalidStreak(ownerUserId);
      if (invalidStreak >= 2) return null;

      return <String, dynamic>{
        'test_type': 'object',
        'image_path': '',
        'recent_invalid_streak': invalidStreak,
      };
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 记忆摘要（给 global）
  // ---------------------------------------------------------------------------

  /// 取 memory_events 按 importance DESC, last_used ASC NULLS FIRST 前 3 条，
  /// 拼接 title + description 截断为短摘要列表。
  static Future<List<String>> _buildMemorySnippets(String ownerUserId) async {
    try {
      final rows = await LocalDatabase.listMemoryEventsForUser(
        ownerUserId,
        limit: 3,
      );
      final snippets = <String>[];
      for (final r in rows) {
        final title = (r['title'] as String?)?.trim() ?? '';
        final desc = (r['description'] as String?)?.trim() ?? '';
        final parts = <String>[];
        if (title.isNotEmpty) parts.add(title);
        if (desc.isNotEmpty) parts.add(desc);
        if (parts.isNotEmpty) {
          snippets.add(parts.join('：'));
        }
      }
      return snippets;
    } catch (_) {
      return <String>[];
    }
  }
}
