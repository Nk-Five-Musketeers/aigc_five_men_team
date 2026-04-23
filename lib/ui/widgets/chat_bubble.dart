import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.timestamp,
  });

  final String message;
  final bool isUser;
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isUser
        ? const Color(0xFFDCEBFF)
        : const Color(0xFFFFFFFF);
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final crossAxis = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD4E2F3)),
          ),
          child: Column(
            crossAxisAlignment: crossAxis,
            children: [
              Text(
                isUser ? '你' : 'BlueCare',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF516885),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.42,
                  color: Color(0xFF1F334D),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatTime(timestamp),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6D8298),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
