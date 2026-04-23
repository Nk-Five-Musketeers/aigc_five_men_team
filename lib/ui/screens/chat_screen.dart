import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/chat_provider.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('暖心对话')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.messages.length,
              itemBuilder: (context, index) {
                final item = provider.messages[index];
                return ChatBubble(
                  message: item.content,
                  isUser: item.isUser,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: '请输入内容',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final text = _controller.text;
                      _controller.clear();
                      await context.read<ChatProvider>().sendMessage(text);
                    },
                    child: const Text('发送'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
