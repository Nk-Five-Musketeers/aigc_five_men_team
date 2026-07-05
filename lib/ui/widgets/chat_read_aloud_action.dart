import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../data/models/chat_message.dart';
import '../../logic/voice_output_provider.dart';

class ChatReadAloudAction extends StatelessWidget {
  const ChatReadAloudAction({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isUser ||
        message.kind == ChatMessageKind.error ||
        message.content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final output = context.watch<VoiceOutputProvider>();
    final isLoading = output.loadingMessageId == message.id;
    final isPlaying = output.playingMessageId == message.id;
    final label = isLoading
        ? '准备中'
        : isPlaying
            ? '停止'
            : '朗读';
    final tooltip = (isLoading || isPlaying) ? '停止朗读' : '朗读这条回复';

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Tooltip(
          message: tooltip,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryDeep,
              minimumSize: const Size(86, 42),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => unawaited(_toggle(context)),
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryDeep,
                    ),
                  )
                : Icon(
                    isPlaying
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_rounded,
                    size: 21,
                  ),
            label: Text(label),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    try {
      await context.read<VoiceOutputProvider>().toggleReadAloud(
            messageId: message.id,
            text: message.content,
            useStreaming: false,
          );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('暂时无法朗读：$error')),
      );
    }
  }
}
