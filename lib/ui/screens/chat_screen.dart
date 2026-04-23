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
  static const List<String> _quickPrompts = <String>[
    '我今天有点焦虑',
    '提醒我喝水',
    '讲一个回忆故事',
  ];

  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit([String? quickText]) async {
    final text = (quickText ?? _controller.text).trim();
    if (text.isEmpty) return;

    _controller.clear();
    await context.read<ChatProvider>().sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('暖心对话')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEAF3FF),
              Color(0xFFF8FBFF),
            ],
          ),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.favorite_outline, color: Color(0xFF0F766E)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '这是前端演示版：支持对话展示、快捷提问与输入发送。',
                      style: TextStyle(
                        color: Color(0xFF115E59),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.88),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD7E5F5)),
                ),
                child: ListView.builder(
                  itemCount: provider.messages.length,
                  itemBuilder: (context, index) {
                    final item = provider.messages[index];
                    return ChatBubble(
                      message: item.content,
                      isUser: item.isUser,
                      timestamp: item.timestamp,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (context, index) {
                  final text = _quickPrompts[index];
                  return ActionChip(
                    label: Text(text),
                    onPressed: () => _submit(text),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _quickPrompts.length,
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          hintText: '请输入内容，例如：我有点想家',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('发送'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
