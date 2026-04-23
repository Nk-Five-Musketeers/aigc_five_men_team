import '../models/chat_message.dart';

class ChatRepository {
  Future<List<ChatMessage>> fetchHistory() async {
    return <ChatMessage>[];
  }
}
