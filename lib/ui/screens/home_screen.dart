import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../core/voice_input/voice_input.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/profile_photo.dart';
import '../../data/models/relation_conflict_record.dart';
import '../../data/local_db/local_database.dart';
import '../../logic/chat_provider.dart';
import 'data_preentry_screen.dart';

enum _AppView { home, memory, recent, preEntry, settings }

/// 应用整体宽度约束 —— 目标设备是手机，桌面预览时整个 App 居中显示
/// 在这个宽度，与一台主流大屏手机的可视宽度接近。
const double _kAppMaxWidth = 430;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _messageController = TextEditingController();

  _AppView _view = _AppView.home;
  bool _keyboardOpen = true;
  bool _networkOnline = false;
  bool _isRecording = false;
  String _speechMode = '自动识别';

  /// `vivo`：录完上传本地代理；`system`：系统听写。
  String _speechEngine = 'vivo';

  @override
  void dispose() {
    unawaited(VoiceInputService.cancelForDispose());
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

  Future<void> _onVoiceButtonTap() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final chat = context.read<ChatProvider>();
    if (chat.isSending) return;

    if (_isRecording) {
      await VoiceInputService.stopFromUser();
      return;
    }

    setState(() => _isRecording = true);
    try {
      final text = await VoiceInputService.listenOnce(
        speechMode: _speechMode,
        engine: _speechEngine,
      );
      if (!mounted) return;
      if (mounted) setState(() => _isRecording = false);

      final trimmed = text.trim();
      final userStopped = VoiceInputService.consumeEndedByUserStop();

      if (trimmed.isNotEmpty) {
        final polished = await chat.polishSpeechBeforeSend(trimmed);
        if (!mounted) return;
        await chat.sendMessage(
          polished,
          networkTimeout: const Duration(seconds: 180),
        );
      } else if (!userStopped) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('没听到内容，请再试一次或使用键盘输入。'),
          ),
        );
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('语音识别初始化超时，请检查麦克风后重试或使用键盘输入。'),
          ),
        );
      }
    } on VoiceInputUnavailableException catch (e) {
      if (mounted) {
        messenger?.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on VoiceInputListenException catch (e) {
      if (mounted) {
        messenger?.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(content: Text('语音识别异常：$e')),
        );
      }
    } finally {
      VoiceInputService.consumeEndedByUserStop();
      if (mounted) setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final showChatInputs = _view == _AppView.home;

    final scaffold = Scaffold(
      backgroundColor: AppTheme.surface0,
      appBar: AppBar(
        toolbarHeight: 84,
        backgroundColor: AppTheme.surface0,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(
          bottom: BorderSide(color: AppTheme.borderHairline, width: 1),
        ),
        titleSpacing: 0,
        centerTitle: true,
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kAppMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '拾忆',
                        style: TextStyle(
                          fontSize: 26,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '有我在，记忆不孤单',
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  online: _networkOnline,
                  onTap: () =>
                      setState(() => _networkOnline = !_networkOnline),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kAppMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chat.pendingRelationConflicts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _RelationConflictBanner(
                    conflict: chat.pendingRelationConflicts.first,
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(child: _buildView()),
                if (showChatInputs) ...[
                  if (_keyboardOpen) ...[
                    _TypingPanel(
                      controller: _messageController,
                      isSending: chat.isSending,
                      onSend: _sendTypedMessage,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _BottomVoiceBar(
                    keyboardOpen: _keyboardOpen,
                    isSending: chat.isSending,
                    isRecording: _isRecording,
                    onKeyboardTap: () {
                      setState(() => _keyboardOpen = !_keyboardOpen);
                    },
                    onVoiceTap: _onVoiceButtonTap,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _BottomNav(
        currentView: _view,
        onSelect: _onNavSelected,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final showFrame = constraints.maxWidth > 480;
        if (!showFrame) {
          return scaffold;
        }
        return ColoredBox(
          color: AppTheme.outerBg,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _kAppMaxWidth,
                  maxHeight: 932,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface0,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppTheme.borderHairline,
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: scaffold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onNavSelected(int index) {
    switch (index) {
      case 0:
        _showView(_AppView.home);
        break;
      case 1:
        _showView(_AppView.memory);
        break;
      case 2:
        _showView(_AppView.recent);
        break;
      case 3:
        _showView(_AppView.settings);
        break;
    }
  }

  Widget _buildView() {
    final chat = context.watch<ChatProvider>();
    switch (_view) {
      case _AppView.home:
        return const _HomeCompanionView(key: ValueKey('home'));
      case _AppView.memory:
        return _MemoryBookView(
          key: ValueKey('memory-${chat.activeUserId}'),
          ownerUserId: chat.activeUserId,
          onBack: () => _showView(_AppView.home),
        );
      case _AppView.recent:
        return _RecentNotesView(
          key: ValueKey('recent-${chat.activeConversationId}'),
          conversationId: chat.activeConversationId,
          onBack: () => _showView(_AppView.home),
        );
      case _AppView.settings:
        return _SettingsView(
          key: ValueKey('settings-${chat.activeUserId}'),
          speechMode: _speechMode,
          speechEngine: _speechEngine,
          networkOnline: _networkOnline,
          onBack: () => _showView(_AppView.home),
          onPreEntryTap: () => _showView(_AppView.preEntry),
          onModeSelected: (value) => setState(() => _speechMode = value),
          onEngineSelected: (value) => setState(() => _speechEngine = value),
          onNetworkTap: () => setState(() => _networkOnline = !_networkOnline),
        );
      case _AppView.preEntry:
        return DataPreentryScreen(
          key: ValueKey('pre-entry-${chat.activeUserId}'),
          ownerUserId: chat.activeUserId,
          onBack: () => _showView(_AppView.settings),
        );
    }
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 2, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '王阿姨，上午好',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '我在这里陪着您，您可以直接和我说话',
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.45,
                    color: AppTheme.textSoft,
                  ),
                ),
              ],
            ),
          ),
          if (messages.isEmpty && !isSending) const _WelcomeBubble(),
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

class _WelcomeBubble extends StatelessWidget {
  const _WelcomeBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusBubble),
            topRight: Radius.circular(AppTheme.radiusBubble),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(AppTheme.radiusBubble),
          ),
          border: Border.all(color: AppTheme.borderHairline, width: 1),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '今天想聊点什么呢？',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '可以说说家里人、最近做的事，或者您年轻时候的故事。',
              style: TextStyle(
                fontSize: 20,
                height: 1.5,
                fontWeight: FontWeight.w400,
                color: AppTheme.textSoft,
              ),
            ),
          ],
        ),
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
    final isPrompt = message.kind == ChatMessageKind.memoryPrompt ||
        message.kind == ChatMessageKind.cognitivePrompt;

    final Widget content = isPrompt
        ? _PromptCard(message: message, onOptionTap: onOptionTap)
        : _MessageBubble(
            text: message.content,
            isUser: message.isUser,
            isError: message.kind == ChatMessageKind.error,
          );

    if (message.isUser) {
      return content;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LetterAvatar(letter: '拾'),
          const SizedBox(width: 8),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(top: 2),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
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
          Text(
            message.title ?? '慢慢想一想',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppTheme.text,
            ),
          ),
          if (message.cueLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              message.cueLabel!,
              style: const TextStyle(
                color: AppTheme.primaryDeep,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            message.content,
            style: const TextStyle(
              fontSize: 23,
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
    final Color bgColor;
    final Color textColor;
    if (isError) {
      bgColor = AppTheme.dangerSoft;
      textColor = const Color(0xFF7A2B1A);
    } else if (isUser) {
      bgColor = AppTheme.primarySoft;
      textColor = Colors.white;
    } else {
      bgColor = AppTheme.surface2;
      textColor = AppTheme.text;
    }
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320, minHeight: 56),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppTheme.radiusBubble),
            topRight: const Radius.circular(AppTheme.radiusBubble),
            bottomLeft: Radius.circular(isUser ? AppTheme.radiusBubble : 6),
            bottomRight: Radius.circular(isUser ? 6 : AppTheme.radiusBubble),
          ),
          border: (isUser || isError)
              ? null
              : Border.all(color: AppTheme.borderHairline, width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 21,
            height: 1.45,
            fontWeight: FontWeight.w500,
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
            '拾忆正在认真听您说...',
            style: TextStyle(color: AppTheme.textSoft, fontSize: 21),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.online, required this.onTap});

  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: online ? AppTheme.surface2 : AppTheme.surface1,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(color: AppTheme.borderHairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: online ? AppTheme.primary : AppTheme.textCaption,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                online ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: online ? AppTheme.primaryDeep : AppTheme.textSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentView, required this.onSelect});

  final _AppView currentView;
  final ValueChanged<int> onSelect;

  int get _index {
    switch (currentView) {
      case _AppView.home:
        return 0;
      case _AppView.memory:
        return 1;
      case _AppView.recent:
        return 2;
      case _AppView.settings:
      case _AppView.preEntry:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface1,
        border: Border(
          top: BorderSide(color: AppTheme.borderHairline, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kAppMaxWidth),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              selectedIndex: _index,
              onDestinationSelected: onSelect,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  selectedIcon: Icon(Icons.chat_bubble_rounded),
                  label: '陪伴',
                ),
                NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: '回忆',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  label: '最近',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: '设置',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryBookView extends StatefulWidget {
  const _MemoryBookView({
    super.key,
    required this.ownerUserId,
    required this.onBack,
  });

  final String ownerUserId;
  final VoidCallback onBack;

  @override
  State<_MemoryBookView> createState() => _MemoryBookViewState();
}

class _MemoryBookViewState extends State<_MemoryBookView> {
  late Future<List<ProfilePhotoModel>> _future;
  ProfilePhotoCategory? _filter;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_MemoryBookView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerUserId != widget.ownerUserId) {
      setState(() => _future = _load());
    }
  }

  Future<List<ProfilePhotoModel>> _load() {
    return LocalDatabase.listProfilePhotosForUser(widget.ownerUserId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(
            '回忆图鉴',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppTheme.text,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            '每一张照片，都可以陪您好好想一想',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSoft,
            ),
          ),
        ),
        _MemoryFilterChips(
          current: _filter,
          onSelect: (cat) => setState(() => _filter = cat),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: FutureBuilder<List<ProfilePhotoModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var photos = snapshot.data!;
              if (_filter != null) {
                photos =
                    photos.where((p) => p.category == _filter).toList();
              }
              if (photos.isEmpty) {
                return const _EmptyHint(
                  title: '相册暂时还是空的',
                  hint: '到「设置 → 数据预录入 → 照片」里慢慢添加',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.only(bottom: 14),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                itemCount: photos.length,
                itemBuilder: (context, index) =>
                    _MemoryPhotoTile(photo: photos[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MemoryFilterChips extends StatelessWidget {
  const _MemoryFilterChips({required this.current, required this.onSelect});

  final ProfilePhotoCategory? current;
  final ValueChanged<ProfilePhotoCategory?> onSelect;

  static const _entries = <(ProfilePhotoCategory?, String)>[
    (null, '全部'),
    (ProfilePhotoCategory.family, '家庭'),
    (ProfilePhotoCategory.memory, '经历'),
    (ProfilePhotoCategory.daily, '日常'),
    (ProfilePhotoCategory.avatar, '头像'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (cat, label) = _entries[index];
          final active = current == cat;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              onTap: () => onSelect(cat),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppTheme.primary : AppTheme.surface1,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: active
                        ? AppTheme.primary
                        : AppTheme.borderHairline,
                    width: 1,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppTheme.text,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MemoryPhotoTile extends StatelessWidget {
  const _MemoryPhotoTile({required this.photo});

  final ProfilePhotoModel photo;

  String get _categoryLabel {
    return switch (photo.category) {
      ProfilePhotoCategory.avatar => '头像',
      ProfilePhotoCategory.family => '家庭',
      ProfilePhotoCategory.memory => '经历',
      ProfilePhotoCategory.daily => '日常',
      ProfilePhotoCategory.other => '其他',
    };
  }

  @override
  Widget build(BuildContext context) {
    final caption = (photo.caption ?? '').trim();
    final subtitle = [
      _categoryLabel,
      if ((photo.photoTime ?? '').trim().isNotEmpty) photo.photoTime!.trim(),
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: AppTheme.surface2,
              child: _MemoryPhotoImage(photo: photo),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        caption.isEmpty ? '未命名' : caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: caption.isEmpty
                              ? AppTheme.textCaption
                              : AppTheme.text,
                        ),
                      ),
                    ),
                    if (photo.isFavorite)
                      const Icon(
                        Icons.bookmark_rounded,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textCaption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryPhotoImage extends StatelessWidget {
  const _MemoryPhotoImage({required this.photo});

  final ProfilePhotoModel photo;

  @override
  Widget build(BuildContext context) {
    final path = photo.filePath;
    if (path.startsWith('data:image/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _MemoryPhotoFallback(),
      );
    }
    if (kIsWeb) {
      return const _MemoryPhotoFallback(hint: 'Web 暂不可预览');
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _MemoryPhotoFallback(),
    );
  }
}

class _MemoryPhotoFallback extends StatelessWidget {
  const _MemoryPhotoFallback({this.hint});

  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.image_outlined,
            color: AppTheme.textCaption,
            size: 28,
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 17,
                color: AppTheme.textCaption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentNotesView extends StatefulWidget {
  const _RecentNotesView({
    super.key,
    required this.conversationId,
    required this.onBack,
  });

  final String conversationId;
  final VoidCallback onBack;

  @override
  State<_RecentNotesView> createState() => _RecentNotesViewState();
}

class _RecentNotesViewState extends State<_RecentNotesView> {
  late Future<List<Map<String, dynamic>>> _historyFuture;
  static const int _historyPageSize = 120;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  @override
  void didUpdateWidget(_RecentNotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _refresh();
    }
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    return LocalDatabase.getRecentMessagesForConversation(
      widget.conversationId,
      limit: _historyPageSize,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _historyFuture = _loadHistory();
    });
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空聊天历史'),
        content: const Text(
          '将删除本机中该会话的全部聊天记录，且不可恢复。确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<ChatProvider>().clearHomeConversationHistory();
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已全部清空')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(
            '最近记录',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppTheme.text,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '自动从本地数据库读取',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSoft,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('刷新'),
              ),
              TextButton.icon(
                onPressed: _confirmClearAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSoft,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const _EmptyHint(
                  title: '还没有聊天记录',
                  hint: '到「陪伴」里聊几句，记录会自动出现在这里',
                );
              }
              final items = _flattenWithHeaders(rows);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 14),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item is String) {
                    return _RecentDateHeader(label: item);
                  }
                  return _ChatHistoryItem(
                    row: item as Map<String, dynamic>,
                    onDeleted: _refresh,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<Object> _flattenWithHeaders(List<Map<String, dynamic>> rows) {
    final out = <Object>[];
    String? currentGroup;
    for (final row in rows) {
      final timestamp =
          DateTime.tryParse(row['timestamp'] as String? ?? '');
      final group = _groupLabel(timestamp);
      if (group != currentGroup) {
        out.add(group);
        currentGroup = group;
      }
      out.add(row);
    }
    return out;
  }

  String _groupLabel(DateTime? ts) {
    if (ts == null) return '未知时间';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tsDay = DateTime(ts.year, ts.month, ts.day);
    if (tsDay == today) return '今天';
    if (tsDay == yesterday) return '昨天';
    final daysAgo = today.difference(tsDay).inDays;
    if (daysAgo < 7) return '更早 · 一周内';
    return '更早';
  }
}

class _RecentDateHeader extends StatelessWidget {
  const _RecentDateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.textCaption,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                height: 1.4,
                fontWeight: FontWeight.w400,
                color: AppTheme.textSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatHistoryItem extends StatelessWidget {
  const _ChatHistoryItem({
    required this.row,
    required this.onDeleted,
  });

  final Map<String, dynamic> row;
  final VoidCallback onDeleted;

  Future<void> _confirmDelete(BuildContext context) async {
    final id = row['id'] as String?;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录'),
        content: const Text('仅从本机删除该条聊天内容，删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<ChatProvider>().deleteMessageById(id);
    if (!context.mounted) return;
    onDeleted();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = (row['user_id'] as String?) != null;
    final timestamp = DateTime.tryParse(row['timestamp'] as String? ?? '');
    final role = isUser ? '我' : '拾忆';
    final timeText = timestamp == null
        ? ''
        : '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    final content = (row['content'] as String? ?? '').trim();
    final isEmpty = content.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      role,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: isUser ? AppTheme.primaryDeep : AppTheme.text,
                      ),
                    ),
                    if (timeText.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        timeText,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textCaption,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isEmpty ? '（空消息）' : content,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    color:
                        isEmpty ? AppTheme.textCaption : AppTheme.text,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _confirmDelete(context),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppTheme.textCaption,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    super.key,
    required this.speechMode,
    required this.speechEngine,
    required this.networkOnline,
    required this.onBack,
    required this.onPreEntryTap,
    required this.onModeSelected,
    required this.onEngineSelected,
    required this.onNetworkTap,
  });

  final String speechMode;
  final String speechEngine;
  final bool networkOnline;
  final VoidCallback onBack;
  final VoidCallback onPreEntryTap;
  final ValueChanged<String> onModeSelected;
  final ValueChanged<String> onEngineSelected;
  final VoidCallback onNetworkTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      children: [
        const _SettingsSectionLabel('数据'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              title: '数据预录入',
              subtitle: '老人信息、亲属、经历与照片统一管理',
              onTap: onPreEntryTap,
              showChevron: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SettingsSectionLabel('语音'),
        _SettingsGroup(
          children: [
            _SettingsSubBlock(
              title: '听写引擎',
              helper: '推荐 vivo，本地代理需启动；失败可改系统识别',
              children: [
                _ModeButton(
                  label: 'vivo 听写（推荐）',
                  active: speechEngine == 'vivo',
                  onTap: () => onEngineSelected('vivo'),
                ),
                _ModeButton(
                  label: '系统听写（备用）',
                  active: speechEngine == 'system',
                  onTap: () => onEngineSelected('system'),
                ),
              ],
            ),
            const _SettingsRowDivider(),
            _SettingsSubBlock(
              title: '系统听写语言',
              helper: '仅在选择「系统听写」时生效',
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
          ],
        ),
        const SizedBox(height: 20),
        const _SettingsSectionLabel('系统'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              title: '是否联网',
              subtitle: '默认离线可用，需要时再联网',
              trailing: _OnOffChip(online: networkOnline),
              onTap: onNetworkTap,
            ),
            const _SettingsRowDivider(),
            const _DatabasePathTile(),
          ],
        ),
      ],
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: AppTheme.textCaption,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SettingsRowDivider extends StatelessWidget {
  const _SettingsRowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppTheme.borderHairline,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 19,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
              if (showChevron) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: AppTheme.textCaption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSubBlock extends StatelessWidget {
  const _SettingsSubBlock({
    required this.title,
    required this.helper,
    required this.children,
  });

  final String title;
  final String helper;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            style: const TextStyle(
              fontSize: 19,
              height: 1.4,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSoft,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _OnOffChip extends StatelessWidget {
  const _OnOffChip({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: online ? AppTheme.primary : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: online ? AppTheme.primary : AppTheme.borderHairline,
          width: 1,
        ),
      ),
      child: Text(
        online ? '已开启' : '已关闭',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: online ? Colors.white : AppTheme.primaryDeep,
        ),
      ),
    );
  }
}

class _DatabasePathTile extends StatelessWidget {
  const _DatabasePathTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: LocalDatabase.getDatabasePathForDebug(),
      builder: (context, snapshot) {
        final path = snapshot.data ?? '读取中...';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '本地数据库文件',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocalDatabase.storageHint(),
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSoft,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                path,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  color: AppTheme.text,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusMedium),
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
    required this.onKeyboardTap,
    required this.onVoiceTap,
  });

  final bool keyboardOpen;
  final bool isSending;
  final bool isRecording;
  final VoidCallback onKeyboardTap;
  final VoidCallback onVoiceTap;

  @override
  Widget build(BuildContext context) {
    final voiceLabel = isSending
        ? '正在回应'
        : isRecording
            ? '正在识别 · 点此结束发送'
            : '点击开始说话';

    final Color voiceColor;
    if (isSending) {
      voiceColor = AppTheme.textSoft;
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
                onTap: isSending ? null : onVoiceTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: voiceColor,
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusLarge),
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

