part of '../home_screen.dart';

class _RelationConflictBanner extends StatelessWidget {
  const _RelationConflictBanner({required this.conflict});

  final RelationConflictRecord conflict;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 4,
            color: AppTheme.accent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.accent,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '人物信息与聊天内容不一致',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                          color: AppTheme.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${conflict.personName} · ${conflict.fieldLabel}',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textCaption,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '原有：${conflict.oldValue ?? '（空）'}\n新提到：${conflict.newValue ?? '（空）'}',
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context
                            .read<ChatProvider>()
                            .resolveRelationConflictUi(conflict.id, false),
                        child: const Text('保留原有'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context
                            .read<ChatProvider>()
                            .resolveRelationConflictUi(conflict.id, true),
                        child: const Text('采用新信息'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingPanel extends StatelessWidget {
  const _TypingPanel({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isSending,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(
                fontSize: 22,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppTheme.text,
              ),
              decoration: const InputDecoration(
                hintText: '输入想说的话',
                hintStyle: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textCaption,
                ),
                filled: false,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 60,
            child: FilledButton(
              onPressed: isSending ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
              ),
              child: Text(
                isSending ? '等待' : '发送',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomVoiceBar extends StatelessWidget {
  const _BottomVoiceBar({
    required this.keyboardOpen,
    required this.isSending,
    required this.isRecording,
    required this.isRecognizing,
    required this.onKeyboardTap,
    required this.onVoiceTap,
  });

  final bool keyboardOpen;
  final bool isSending;
  final bool isRecording;
  final bool isRecognizing;
  final VoidCallback onKeyboardTap;
  final VoidCallback onVoiceTap;

  @override
  Widget build(BuildContext context) {
    final voiceBusy = isSending || isRecognizing;
    final voiceLabel = isSending
        ? '正在回应'
        : isRecognizing
            ? '正在识别说话'
            : isRecording
                ? '正在说话 · 点此结束'
                : '点击开始说话';

    final Color voiceColor;
    if (isSending) {
      voiceColor = AppTheme.textSoft;
    } else if (isRecognizing) {
      voiceColor = AppTheme.primary;
    } else if (isRecording) {
      voiceColor = const Color(0xFFD8624A);
    } else {
      voiceColor = AppTheme.primary;
    }

    return SizedBox(
      height: 88,
      child: Row(
        children: [
          _SideAction(
            label: '键盘',
            icon: Icons.keyboard_alt_outlined,
            active: keyboardOpen,
            onTap: onKeyboardTap,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                onTap: voiceBusy ? null : onVoiceTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: voiceColor,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    boxShadow: isRecording
                        ? [
                            BoxShadow(
                              color: voiceColor.withValues(alpha: 0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isRecognizing)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        else
                          Icon(
                            isRecording
                                ? Icons.stop_circle_outlined
                                : Icons.mic_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          voiceLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SideAction(
            label: '附件',
            icon: Icons.add_rounded,
            active: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: onTap,
        child: Container(
          width: 68,
          height: 88,
          decoration: BoxDecoration(
            color: active ? AppTheme.surface2 : AppTheme.surface1,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: AppTheme.borderHairline, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: active ? AppTheme.primaryDeep : AppTheme.textSoft,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: active ? AppTheme.primaryDeep : AppTheme.textSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: active ? AppTheme.primary : AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: active ? AppTheme.primary : AppTheme.borderHairline,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppTheme.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
