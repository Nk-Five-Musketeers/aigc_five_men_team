import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../logic/chat_provider.dart';
import '../../data/models/chat_message.dart';

enum _AppView { home, memory, recent, settings }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _AppView _view = _AppView.home;
  bool _keyboardOpen = false;
  bool _networkOnline = false;
  String _speechMode = '自动识别';
  final TextEditingController _controller = TextEditingController();

  void _showView(_AppView view) {
    setState(() => _view = view);
  }

  Future<void> _submit([String? quickText]) async {
    final text = (quickText ?? _controller.text).trim();
    if (text.isEmpty) return;

    _controller.clear();
    await context.read<ChatProvider>().sendMessage(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4FAFF), Color(0xFFEAF4FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                decoration: _phoneDecoration,
                child: Column(
                  children: [
                    _Header(
                      onSettingsTap: () => _showView(_AppView.settings),
                      onMemoryTap: () => _showView(_AppView.memory),
                      onRecentTap: () => _showView(_AppView.recent),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _buildView(chatProvider),
                      ),
                    ),
                    if (_keyboardOpen)
                      _TypingPanel(
                        controller: _controller,
                        onSend: _submit,
                        isLoading: chatProvider.isLoading,
                      ),
                    const SizedBox(height: 10),
                    _BottomAction(
                      keyboardOpen: _keyboardOpen,
                      onKeyboardTap: () {
                        setState(() => _keyboardOpen = !_keyboardOpen);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildView(ChatProvider chatProvider) {
    return switch (_view) {
      _AppView.home => _HomeView(
          key: const ValueKey('home'),
          messages: chatProvider.messages,
          isLoading: chatProvider.isLoading,
        ),
      _AppView.memory => _MemoryView(
          key: const ValueKey('memory'),
          onBack: () => _showView(_AppView.home),
        ),
      _AppView.recent => _RecentView(
          key: const ValueKey('recent'),
          onBack: () => _showView(_AppView.home),
        ),
      _AppView.settings => _SettingsView(
          key: const ValueKey('settings'),
          speechMode: _speechMode,
          networkOnline: _networkOnline,
          onBack: () => _showView(_AppView.home),
          onModeSelected: (value) => setState(() => _speechMode = value),
          onNetworkTap: () {
            setState(() => _networkOnline = !_networkOnline);
          },
        ),
    };
  }

  BoxDecoration get _phoneDecoration {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(38),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xF0FFFFFF), Color(0xF5F1F8FF)],
      ),
      border: Border.all(color: const Color(0x2975ADE4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2E5285B9),
          blurRadius: 80,
          offset: Offset(0, 30),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onSettingsTap,
    required this.onMemoryTap,
    required this.onRecentTap,
  });

  final VoidCallback onSettingsTap;
  final VoidCallback onMemoryTap;
  final VoidCallback onRecentTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: SizedBox(height: 46)),
              _SoftButton(
                label: '设置',
                minWidth: 84,
                onTap: onSettingsTap,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SoftButton(label: '回忆图鉴', onTap: onMemoryTap),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SoftButton(label: '最近记录', onTap: onRecentTap),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({super.key, required this.messages, required this.isLoading});

  final List<ChatMessage> messages;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _HeroCard(messages: messages, isLoading: isLoading),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.messages, required this.isLoading});

  final List<ChatMessage> messages;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TinyTag(label: '离线陪伴'),
          const SizedBox(height: 12),
          const Text(
            '王阿姨，上午好',
            style: TextStyle(
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '您可以直接和我说说话',
            style: TextStyle(fontSize: 14, color: AppTheme.textSoft),
          ),
          const SizedBox(height: 18),
          _ChatPreview(messages: messages, isLoading: isLoading),
        ],
      ),
    );
  }
}

class _ChatPreview extends StatelessWidget {
  const _ChatPreview({required this.messages, required this.isLoading});

  final List<ChatMessage> messages;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final actualMessages = messages.length > 1 ? messages.sublist(1) : <ChatMessage>[];
    if (actualMessages.isEmpty) {
      return const Column(
        children: [
          _MessageBubble(text: '今天想聊什么？', isUser: false),
          _MessageBubble(text: '我想看看以前的照片。', isUser: true),
          _MessageBubble(text: '好，我陪您慢慢看。', isUser: false),
        ],
      );
    }

    final displayMessages = actualMessages.length > 3
        ? actualMessages.sublist(actualMessages.length - 3)
        : actualMessages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in displayMessages)
          _MessageBubble(text: message.content, isUser: message.isUser),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _MemoryView extends StatelessWidget {
  const _MemoryView({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _TitleRow(label: '回忆', onBack: onBack),
        const SizedBox(height: 14),
        _Surface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Row(
                children: [
                  Expanded(child: _MemoryPhoto(colorA: Color(0xFFD3E9FF), colorB: Color(0xFF8FC8FD))),
                  SizedBox(width: 10),
                  Expanded(child: _MemoryPhoto(colorA: Color(0xFFEBF5FF), colorB: Color(0xFFB0D8FF))),
                ],
              ),
              SizedBox(height: 14),
              Text('春天里的自行车', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.text)),
              SizedBox(height: 4),
              Text('1986', style: TextStyle(fontSize: 14, color: AppTheme.textSoft)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Surface(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: const [
                  _AvatarBox(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('这是谁？', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.text)),
                        SizedBox(height: 4),
                        Text('可以慢慢想', style: TextStyle(fontSize: 14, color: AppTheme.textSoft)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  Expanded(child: _AnswerButton(label: '女儿')),
                  SizedBox(width: 8),
                  Expanded(child: _AnswerButton(label: '邻居')),
                  SizedBox(width: 8),
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

class _RecentView extends StatelessWidget {
  const _RecentView({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _TitleRow(label: '最近', onBack: onBack),
        const SizedBox(height: 14),
        _Surface(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: const [
              _MiniItem(text: '提到女儿的旧照片'),
              _MiniItem(text: '说中午吃了面'),
              _MiniItem(text: '聊到以前骑自行车'),
              _MiniItem(text: '午休情况正常'),
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
        _TitleRow(label: '设置', onBack: onBack),
        const SizedBox(height: 14),
        _SettingsCard(
          title: '录入数据',
          description: '提前录入，后续聊天可继续补充',
          child: Column(
            children: const [
              _SettingsRow(title: '基本信息'),
              _SettingsRow(title: '家庭照片'),
              _SettingsRow(title: '重要经历'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          title: '语音识别模式',
          description: '默认自动识别，也可手动切换优先模式',
          child: Column(
            children: [
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
        _SettingsCard(
          title: '联网状态',
          description: '默认离线可用，需要时再联网',
          child: _NetworkRow(
            online: networkOnline,
            onTap: onNetworkTap,
          ),
        ),
      ],
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x295B91C6),
            blurRadius: 42,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({
    required this.label,
    required this.onTap,
    this.minWidth,
  });

  final String label;
  final VoidCallback onTap;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: minWidth,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.82),
          foregroundColor: AppTheme.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppTheme.line),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _TinyTag extends StatelessWidget {
  const _TinyTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.blueSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.blueDeep,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SoftButton(label: '返回', minWidth: 82, onTap: onBack),
        const Spacer(),
        _TinyTag(label: label),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(colors: [Color(0xFF7CBCF8), Color(0xFF61A8EF)])
              : null,
          color: isUser ? null : const Color(0xFFF4F9FF),
          borderRadius: BorderRadius.circular(20),
          border: isUser ? null : Border.all(color: const Color(0x1F6EA8E1)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : AppTheme.text,
            fontSize: 19,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

class _MemoryPhoto extends StatelessWidget {
  const _MemoryPhoto({required this.colorA, required this.colorB});

  final Color colorA;
  final Color colorB;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.82,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colorA, colorB],
          ),
        ),
        child: const Icon(
          Icons.photo_camera_back_outlined,
          color: Colors.white,
          size: 38,
        ),
      ),
    );
  }
}

class _AvatarBox extends StatelessWidget {
  const _AvatarBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF92CBFF), Color(0xFF6AAEF0)],
        ),
      ),
      child: const Icon(Icons.person_outline, color: Colors.white, size: 36),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFF6FBFF),
          foregroundColor: AppTheme.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _MiniItem extends StatelessWidget {
  const _MiniItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppTheme.blue,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x296AAEF1), spreadRadius: 5),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 17, color: AppTheme.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppTheme.textSoft,
            ),
          ),
          const SizedBox(height: 14),
          child,
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
        color: const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(18),
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
          const _TinyTag(label: '进入'),
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
        borderRadius: BorderRadius.circular(18),
        gradient: active
            ? const LinearGradient(colors: [Color(0xFF79BBFF), Color(0xFF5BA5ED)])
            : null,
        color: active ? null : const Color(0xFFF7FBFF),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: active ? Colors.white : AppTheme.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: online ? const Color(0xFFE3F0FF) : const Color(0xFFF7FBFF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '是否联网',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 72),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: online ? AppTheme.blueDeep : AppTheme.blueSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                online ? '已开启' : '已关闭',
                style: TextStyle(
                  color: online ? Colors.white : AppTheme.blueDeep,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingPanel extends StatelessWidget {
  const _TypingPanel({
    required this.controller,
    required this.onSend,
    required this.isLoading,
  });

  final TextEditingController controller;
  final Future<void> Function() onSend;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSend(),
              enabled: !isLoading,
              decoration: InputDecoration(
                hintText: '输入想说的话',
                filled: true,
                fillColor: const Color(0xFFF8FBFF),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0x296EA8E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0x296EA8E1)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF75B8FB), Color(0xFF569FE8)],
              ),
            ),
            child: TextButton(
              onPressed: isLoading ? null : onSend,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              ),
              child: const Text(
                '发送',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.keyboardOpen,
    required this.onKeyboardTap,
  });

  final bool keyboardOpen;
  final VoidCallback onKeyboardTap;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          _KeyboardButton(active: keyboardOpen, onTap: onKeyboardTap),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 86),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF79BBFF), Color(0xFF529EE9)],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x475399E1),
                    blurRadius: 34,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic_none_rounded, color: Colors.white, size: 32),
                  SizedBox(height: 8),
                  Text(
                    '按这里说话',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 74),
        ],
      ),
    );
  }
}

class _KeyboardButton extends StatelessWidget {
  const _KeyboardButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: IconButton(
        tooltip: '键盘输入',
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: active ? const Color(0xFFDCEEFF) : const Color(0xFFF7FBFF),
          foregroundColor: active ? AppTheme.blueDeep : AppTheme.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        icon: const Icon(Icons.keyboard_alt_outlined, size: 28),
      ),
    );
  }
}
