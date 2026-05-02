import '../../core/api_client.dart';
import '../models/chat_message.dart';
import '../models/daily_note.dart';
import '../models/memory_item.dart';

class DebugMemoryExporter {
  DebugMemoryExporter({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<void> exportConversationMessage(ChatMessage message) async {
    await _postTableUpdates(
      <String, List<Map<String, Object?>>>{
        'conversation_records': <Map<String, Object?>>[
          <String, Object?>{
            'id': message.timestamp.microsecondsSinceEpoch,
            'session_date': message.timestamp.toIso8601String(),
            'duration': 0,
            'dialog_json': <String, Object?>{
              'id': message.id,
              'content': message.content,
              'is_user': message.isUser,
              'timestamp': message.timestamp.toIso8601String(),
              'kind': message.kind.name,
              'title': message.title,
              'cue_label': message.cueLabel,
              'options': message.options,
            },
            'new_memories': null,
            'cognitive_score': null,
            'quiz_results': null,
            'processed': false,
          },
        ],
      },
    );
  }

  Future<void> exportExtraction({
    required ChatMessage sourceMessage,
    required Map<String, Object?> elderProfile,
    required List<Map<String, Object?>> familyMembers,
    required List<MemoryItem> memoryEvents,
    required DailyNote? dailyRecord,
  }) async {
    if (elderProfile.isEmpty &&
        familyMembers.isEmpty &&
        memoryEvents.isEmpty &&
        dailyRecord == null) {
      return;
    }

    await _postTableUpdates(
      <String, List<Map<String, Object?>>>{
        if (elderProfile.isNotEmpty)
          'elder_basic_info': <Map<String, Object?>>[
            <String, Object?>{
              'source_message_id': sourceMessage.id,
              ...elderProfile,
            },
          ],
        if (familyMembers.isNotEmpty) 'family_members': familyMembers,
        if (memoryEvents.isNotEmpty)
          'memory_events': memoryEvents.map((item) => item.toMap()).toList(),
        if (dailyRecord != null)
          'daily_life_records': <Map<String, Object?>>[dailyRecord.toMap()],
      },
    );
  }

  Future<void> _postTableUpdates(
    Map<String, List<Map<String, Object?>>> tableUpdates,
  ) async {
    if (tableUpdates.isEmpty) return;

    try {
      await _apiClient.dio.post<void>(
        '/api/debug/memory-export',
        data: <String, Object?>{
          'exported_at': DateTime.now().toIso8601String(),
          'table_updates': tableUpdates,
        },
      );
    } catch (_) {
      // Debug export must never interrupt the chat or memory flow.
    }
  }
}
