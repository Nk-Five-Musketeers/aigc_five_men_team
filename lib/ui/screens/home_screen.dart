import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../data/models/chat_message.dart';
import '../../logic/chat_provider.dart';

enum _AppView { home, memory, recent, settings }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _messageController = TextEditingController();

  _AppView _view = _AppView.home;
  bool _keyboardOpen = false;
  bool _networkOnline = false;
  String _speechMode = '自动识别';
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _showView(_AppView view) {
    setState(() => _view = view);
  }

  Future<void> _sendTypedMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await context.read<ChatProvider>().sendMessage(text);
  }

  Future<void> _sendVoiceDemoPrompt() async {
    await context.read<ChatProvider>().sendMessage('我想和你聊聊今天的事。');
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.backgroundWarm,
              AppTheme.background,
              Color(0xFFFFF2DE),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 460;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Container(
                    margin: EdgeInsets.all(compact ? 0 : 16),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: _phoneDecoration(compact),
                    child: Column(
                      children: [
                        _BrandHeader(
                          activeView: _view,
                          onSettingsTap: () => _showView(_AppView.settings),
                          onMemoryTap: () => _showView(_AppView.memory),
                          onRecentTap: () => _showView(_AppView.recent),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            child: _buildView(),
                          ),
                        ),
                        if (_keyboardOpen)
                          _TypingPanel(
                            controller: _messageController,
                            isSending: chat.isSending,
                            onSend: _sendTypedMessage,
                          ),
                        const SizedBox(height: 10),
                        _BottomVoiceBar(
                          keyboardOpen: _keyboardOpen,
                          isSending: chat.isSending,
                          onKeyboardTap: () {
                            setState(() => _keyboardOpen = !_keyboardOpen);
                          },
                          onVoiceTap: _sendVoiceDemoPrompt,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildView() {
    switch (_view) {
      case _AppView.home:
        return const _HomeCompanionView(key: ValueKey('home'));
      case _AppView.memory:
        return _MemoryBookView(
          key: const ValueKey('memory'),
          onBack: () => _showView(_AppView.home),
        );
      case _AppView.recent:
        return _RecentNotesView(
          key: const ValueKey('recent'),
          onBack: () => _showView(_AppView.home),
        );
      case _AppView.settings:
        return _SettingsView(
          key: const ValueKey('settings'),
          speechMode: _speechMode,
          networkOnline: _networkOnline,
          onBack: () => _showView(_AppView.home),
          onModeSelected: (value) => setState(() => _speechMode = value),
          onNetworkTap: () => setState(() => _networkOnline = !_networkOnline),
        );
    }
  }

  BoxDecoration _phoneDecoration(bool compact) {
    return BoxDecoration(
      color: AppTheme.backgroundWarm.withOpacity(0.96),
      borderRadius: BorderRadius.circular(compact ? 0 : 34),
      border: compact ? null : Border.all(color: AppTheme.border),
      boxShadow: compact
          ? const []
          : const [
              BoxShadow(
                color: Color(0x22A36B32),
                blurRadius: 42,
                offset: Offset(0, 24),
              ),
            ],
    );
  }
}

class _HomeCompanionView extends StatelessWidget {
  const _HomeCompanionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 14),
          children: [
            _ChatCompanionCard(
              messages: chat.messages,
              isSending: chat.isSending,
              onOptionTap: chat.sendOption,
            ),
          ],
        );
      },
    );
  }
}

class _ChatCompanionCard extends StatelessWidget {
  const _ChatCompanionCard({
    required this.messages,
    required this.isSending,
    required this.onOptionTap,
  });

  final List<ChatMessage> messages;
  final bool isSending;
  final ValueChanged<String> onOptionTap;

  @override
  Widget build(BuildContext context) {
    return _WarmCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '王阿姨，上午好',
                      style: TextStyle(
                        fontSize: 31,
                        height: 1.18,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.text,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '我在这里陪着您，您可以直接和我说话',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.45,
                        color: AppTheme.textSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.wb_sunny_rounded,
                  color: AppTheme.accent,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _StatusPill(),
          const SizedBox(height: 20),
          ...messages.map(
            (message) => _ChatMessageView(
              message: message,
              onOptionTap: onOptionTap,
            ),
          ),
          if (isSending) const _TypingIndicator(),
        ],
      ),
    );
  }
}

class _ChatMessageView extends StatelessWidget {
  const _ChatMessageView({
    required this.message,
    required this.onOptionTap,
  });

  final ChatMessage message;
  final ValueChanged<String> onOptionTap;

  @override
  Widget build(BuildContext context) {
    if (message.kind == ChatMessageKind.memoryPrompt ||
        message.kind == ChatMessageKind.cognitivePrompt) {
      return _PromptCard(message: message, onOptionTap: onOptionTap);
    }
    return _MessageBubble(
      text: message.content,
      isUser: message.isUser,
      isError: message.kind == ChatMessageKind.error,
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.message,
    required this.onOptionTap,
  });

  final ChatMessage message;
  final ValueChanged<String> onOptionTap;

  @override
  Widget build(BuildContext context) {
    final isCognitive = message.kind == ChatMessageKind.cognitivePrompt;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCognitive ? const Color(0xFFFFF3E1) : AppTheme.successSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCognitive ? Icons.psychology_alt_rounded : Icons.eco_rounded,
                color: isCognitive ? AppTheme.accent : AppTheme.primaryDeep,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.title ?? '慢慢想一想',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ],
          ),
          if (message.cueLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              message.cueLabel!,
              style: const TextStyle(
                color: AppTheme.primaryDeep,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            message.content,
            style: const TextStyle(
              fontSize: 17,
              height: 1.45,
              color: AppTheme.text,
            ),
          ),
          if (message.options.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.options
                  .map(
                    (option) => ActionChip(
                      label: Text(option),
                      onPressed: () => onOptionTap(option),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppTheme.border),
                      labelStyle: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isUser,
    this.isError = false,
  });

  final String text;
  final bool isUser;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310, minHeight: 54),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
        decoration: BoxDecoration(
          color: isError
              ? const Color(0xFFFFECE4)
              : isUser
                  ? AppTheme.primary
                  : const Color(0xFFFFF3E1),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isUser ? 22 : 8),
            bottomRight: Radius.circular(isUser ? 8 : 22),
          ),
          border: isUser ? null : Border.all(color: AppTheme.border),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : AppTheme.text,
            fontSize: 19,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            '暖忆正在认真听您说...',
            style: TextStyle(color: AppTheme.textSoft, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.activeView,
    required this.onSettingsTap,
    required this.onMemoryTap,
    required this.onRecentTap,
  });

  final _AppView activeView;
  final VoidCallback onSettingsTap;
  final VoidCallback onMemoryTap;
  final VoidCallback onRecentTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _CompanionAvatar(),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '暖忆陪伴',
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.text,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '有我在，记忆不孤单',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSoft,
                      ),
                    ),
                  ],
                ),
              ),
              _IconTextButton(
                icon: Icons.tune_rounded,
                label: '设置',
                onTap: onSettingsTap,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _NavCard(
                  icon: Icons.photo_album_rounded,
                  title: '回忆图鉴',
                  subtitle: '看看珍贵的照片',
                  selected: activeView == _AppView.memory,
                  onTap: onMemoryTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavCard(
                  icon: Icons.event_note_rounded,
                  title: '最近记录',
                  subtitle: '看看今天的点滴',
                  selected: activeView == _AppView.recent,
                  onTap: onRecentTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryBookView extends StatelessWidget {
  const _MemoryBookView({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _BackLine(title: '回忆图鉴', onBack: onBack),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SectionTitle(
                icon: Icons.auto_stories_rounded,
                title: '慢慢翻看的老相册',
                subtitle: '每一张照片，都可以陪您好好想一想',
              ),
              SizedBox(height: 16),
              _MemoryPhotoCard(
                title: '春天里的自行车',
                year: '1986',
                accent: AppTheme.primary,
                icon: Icons.directions_bike_rounded,
              ),
              SizedBox(height: 12),
              _MemoryPhotoCard(
                title: '老家小院的午后',
                year: '1983',
                accent: AppTheme.accent,
                icon: Icons.home_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Row(
                children: [
                  _SoftPortrait(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '这是谁？',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.text,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '可以慢慢想，不着急',
                          style: TextStyle(fontSize: 16, color: AppTheme.textSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _AnswerButton(label: '女儿')),
                  SizedBox(width: 10),
                  Expanded(child: _AnswerButton(label: '邻居')),
                  SizedBox(width: 10),
                  Expanded(child: _AnswerButton(label: '再想想')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentNotesView extends StatelessWidget {
  const _RecentNotesView({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _BackLine(title: '最近记录', onBack: onBack),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SectionTitle(
                icon: Icons.favorite_rounded,
                title: '今天的记录',
                subtitle: '最近发生的点滴',
              ),
              SizedBox(height: 16),
              _RecordItem(
                icon: Icons.photo_rounded,
                title: '提到女儿的旧照片',
                description: '看到老照片时，笑着说起女儿小时候的事。',
                color: AppTheme.primary,
              ),
              _RecordItem(
                icon: Icons.ramen_dining_rounded,
                title: '说中午吃了面',
                description: '午饭吃了面条，胃口不错。',
                color: AppTheme.accent,
              ),
              _RecordItem(
                icon: Icons.directions_bike_rounded,
                title: '聊到以前骑自行车',
                description: '说以前常骑车去上班，很轻松很快乐。',
                color: Color(0xFF8FB46D),
              ),
              _RecordItem(
                icon: Icons.night_shelter_rounded,
                title: '午休情况正常',
                description: '中午休息得不错，精神挺好。',
                color: Color(0xFF7FA6A2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    super.key,
    required this.speechMode,
    required this.networkOnline,
    required this.onBack,
    required this.onModeSelected,
    required this.onNetworkTap,
  });

  final String speechMode;
  final bool networkOnline;
  final VoidCallback onBack;
  final ValueChanged<String> onModeSelected;
  final VoidCallback onNetworkTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _BackLine(title: '设置', onBack: onBack),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SectionTitle(
                icon: Icons.shield_rounded,
                title: '本地守护',
                subtitle: '提前录入，后续聊天可继续补充',
              ),
              SizedBox(height: 16),
              _SettingsRow(title: '基本信息'),
              _SettingsRow(title: '家庭照片'),
              _SettingsRow(title: '重要经历'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.record_voice_over_rounded,
                title: '语音识别模式',
                subtitle: '默认自动识别，也可手动切换优先模式',
              ),
              const SizedBox(height: 16),
              _ModeButton(
                label: '自动识别',
                active: speechMode == '自动识别',
                onTap: () => onModeSelected('自动识别'),
              ),
              _ModeButton(
                label: '普通话优先',
                active: speechMode == '普通话优先',
                onTap: () => onModeSelected('普通话优先'),
              ),
              _ModeButton(
                label: '方言优先',
                active: speechMode == '方言优先',
                onTap: () => onModeSelected('方言优先'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.wifi_off_rounded,
                title: '联网状态',
                subtitle: '默认离线可用，需要时再联网',
              ),
              const SizedBox(height: 16),
              _NetworkRow(online: networkOnline, onTap: onNetworkTap),
            ],
          ),
        ),
      ],
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
    return _WarmCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isSending,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 18, color: AppTheme.text),
              decoration: InputDecoration(
                hintText: '输入想说的话',
                hintStyle: const TextStyle(color: AppTheme.textSoft),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: isSending ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                isSending ? '等待' : '发送',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
    required this.onKeyboardTap,
    required this.onVoiceTap,
  });

  final bool keyboardOpen;
  final bool isSending;
  final VoidCallback onKeyboardTap;
  final VoidCallback onVoiceTap;

  @override
  Widget build(BuildContext context) {
    return _WarmCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: IconButton(
              tooltip: '键盘输入',
              onPressed: onKeyboardTap,
              style: IconButton.styleFrom(
                backgroundColor: keyboardOpen ? AppTheme.successSoft : Colors.white,
                foregroundColor: keyboardOpen ? AppTheme.primaryDeep : AppTheme.textSoft,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                side: const BorderSide(color: AppTheme.border),
              ),
              icon: const Icon(Icons.keyboard_alt_rounded, size: 28),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: isSending ? null : onVoiceTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 90),
                decoration: BoxDecoration(
                  color: isSending ? AppTheme.textSoft : AppTheme.primary,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x333FAEA3),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mic_rounded, color: Colors.white, size: 34),
                    const SizedBox(height: 7),
                    Text(
                      isSending ? '正在回应' : '按这里说话',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '松开结束',
                      style: TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 72),
        ],
      ),
    );
  }
}

class _WarmCard extends StatelessWidget {
  const _WarmCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18A36B32),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.successSoft,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFD4EEE9)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_rounded, size: 19, color: AppTheme.primaryDeep),
          SizedBox(width: 7),
          Text(
            '离线陪伴 · 本地守护',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryDeep,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanionAvatar extends StatelessWidget {
  const _CompanionAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.volunteer_activism_rounded,
            color: AppTheme.primaryDeep,
            size: 31,
          ),
          Positioned(
            right: 10,
            top: 9,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.successSoft : AppTheme.cardWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14A36B32),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? AppTheme.primaryDeep : AppTheme.accent, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackLine extends StatelessWidget {
  const _BackLine({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconTextButton(
          icon: Icons.arrow_back_rounded,
          label: '返回',
          onTap: onBack,
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.accentSoft,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppTheme.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.successSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: AppTheme.primaryDeep, size: 25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: AppTheme.textSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemoryPhotoCard extends StatelessWidget {
  const _MemoryPhotoCard({
    required this.title,
    required this.year,
    required this.accent,
    required this.icon,
  });

  final String title;
  final String year;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 96,
            height: 112,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.22)),
            ),
            child: Stack(
              children: [
                Center(child: Icon(icon, size: 38, color: accent)),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Icon(Icons.eco_rounded, size: 17, color: accent.withOpacity(0.8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  year,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSoft,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '像翻开一本旧相册，慢慢看，慢慢想。',
                  style: TextStyle(fontSize: 15, height: 1.35, color: AppTheme.textSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftPortrait extends StatelessWidget {
  const _SoftPortrait();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Icon(
        Icons.face_retouching_natural_rounded,
        color: AppTheme.primaryDeep,
        size: 38,
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          backgroundColor: label == '再想想' ? AppTheme.accentSoft : AppTheme.successSoft,
          foregroundColor: label == '再想想' ? AppTheme.text : AppTheme.primaryDeep,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _RecordItem extends StatelessWidget {
  const _RecordItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              Container(
                width: 2,
                height: 42,
                margin: const EdgeInsets.only(top: 6),
                color: AppTheme.border,
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: AppTheme.textSoft,
                    ),
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

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.text,
              ),
            ),
          ),
          const Text(
            '进入',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryDeep,
            ),
          ),
        ],
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
      height: 56,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: active ? AppTheme.primary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppTheme.primary : AppTheme.border),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: active ? Colors.white : AppTheme.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({required this.online, required this.onTap});

  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: online ? AppTheme.successSoft : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: online ? const Color(0xFFD4EEE9) : AppTheme.border),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '是否联网',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.text,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 78),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: online ? AppTheme.primary : AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.center,
              child: Text(
                online ? '已开启' : '已关闭',
                style: TextStyle(
                  color: online ? Colors.white : AppTheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconTextButton extends StatelessWidget {
  const _IconTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          backgroundColor: AppTheme.cardWhite,
          foregroundColor: AppTheme.text,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppTheme.border),
          ),
        ),
      ),
    );
  }
}
