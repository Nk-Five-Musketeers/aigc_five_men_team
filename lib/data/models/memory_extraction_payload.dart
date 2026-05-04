import 'extracted_relation_hint.dart';

/// 大模型一次返回的「老人档案 + 亲友 + 记忆事件 + 每日生活」抽取结果。
class MemoryExtractionPayload {
  const MemoryExtractionPayload({
    required this.people,
    this.elderProfilePatch = const {},
    this.familyMemberRows = const [],
    this.memoryEventRows = const [],
    this.dailyLifePatch,
    this.rawAssistantJson,
  });

  final List<ExtractedRelationHint> people;

  /// 仅含非空字符串，键为 [users] 表列名（snake_case）。
  final Map<String, String> elderProfilePatch;

  /// 每条已规范为可交给 [LocalDatabase.insertFamilyMember] / update 的字段（不含 id / owner_user_id）。
  final List<Map<String, dynamic>> familyMemberRows;

  /// 每条不含 id / owner_user_id，由上层写入 [memory_events]。
  final List<Map<String, dynamic>> memoryEventRows;

  /// 单日生活片段，键含 date、各餐食与活动等。
  final Map<String, dynamic>? dailyLifePatch;

  /// 模型原始 JSON 字符串（用于 daily_life.raw_extract 等）。
  final String? rawAssistantJson;

  static MemoryExtractionPayload empty() => const MemoryExtractionPayload(
        people: [],
      );
}
