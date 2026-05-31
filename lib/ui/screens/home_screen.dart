import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/services/chat_attachment_service.dart';
import '../../ui/widgets/media_viewer.dart';
import '../../config/theme.dart';
import '../../core/narration/narration_player.dart';
import '../../core/utils/caption_text.dart';
import '../../core/voice_input/voice_input.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/memory_album.dart';
import '../../data/models/profile_photo.dart';
import '../../data/models/relation_conflict_record.dart';
import '../../data/local_db/local_database.dart';
import '../../data/repositories/memory_album_repository.dart';
import '../../logic/chat_provider.dart';
import 'data_preentry_screen.dart';
import '../widgets/chat_read_aloud_action.dart';
import '../widgets/read_aloud_settings_controls.dart';

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
  bool _isRecognizing = false;
  String _speechMode = '自动识别';

  /// `vivo`：录完上传本地代理；`system`：系统听写。
  String _speechEngine = 'vivo';

  int _memoryRefreshToken = 0;

  /// 已选但未发送的附件（需点「发送」才进入对话）。
  PickedChatAttachment? _pendingAttachment;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(VoiceInputService.cancelForDispose());
    _messageController.dispose();
    super.dispose();
  }

  void _onPreEntryDataChanged() {
    context.read<ChatProvider>().reloadUserArchive();
    setState(() => _memoryRefreshToken++);
  }

  void _showView(_AppView view) {
    setState(() => _view = view);
  }

  Future<void> _onSendTap() async {
    final chat = context.read<ChatProvider>();
    if (chat.isSending) return;

    final text = _messageController.text.trim();
    final pending = _pendingAttachment;
    if (pending == null && text.isEmpty) return;

    _messageController.clear();
    if (pending != null) {
      setState(() => _pendingAttachment = null);
      await chat.sendAttachment(
        pending,
        caption: text.isEmpty ? null : text,
      );
    } else {
      await chat.sendMessage(text);
    }
  }

  Future<void> _onAttachmentTap() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final chat = context.read<ChatProvider>();
    if (chat.isSending) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '添加附件',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_outlined, color: AppTheme.primaryDeep),
                  title: const Text('选择照片', style: TextStyle(fontSize: 20)),
                  onTap: () => Navigator.pop(context, 'image'),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined, color: AppTheme.primaryDeep),
                  title: const Text('选择视频', style: TextStyle(fontSize: 20)),
                  onTap: () => Navigator.pop(context, 'video'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;

    try {
      final picked = choice == 'video'
          ? await ChatAttachmentService.pickVideo()
          : await ChatAttachmentService.pickImage();
      if (!mounted || picked == null) return;

      setState(() {
        _pendingAttachment = picked;
        _keyboardOpen = true;
      });
    } catch (e) {
      final message = e is ChatAttachmentException ? e.message : '附件选择失败：$e';
      messenger?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _dismissKeyboardInput({bool closeInputPanel = false}) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (closeInputPanel && _keyboardOpen) {
      setState(() => _keyboardOpen = false);
    }
  }

  Future<void> _onVoiceButtonTap() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final chat = context.read<ChatProvider>();
    if (chat.isSending || _isRecognizing) return;

    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _isRecognizing = true;
      });
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
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isRecognizing = false;
        });
      }
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
                  onTap: () => setState(() => _networkOnline = !_networkOnline),
                ),
              ],
            ),
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboardInput,
        child: Align(
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
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _dismissKeyboardInput(closeInputPanel: true),
                      child: _buildView(),
                    ),
                  ),
                  if (showChatInputs) ...[
                    if (_keyboardOpen) ...[
                      _TypingPanel(
                        controller: _messageController,
                        isSending: chat.isSending,
                        pendingAttachment: _pendingAttachment,
                        onRemoveAttachment: () {
                          setState(() => _pendingAttachment = null);
                        },
                        onSend: _onSendTap,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _BottomVoiceBar(
                      keyboardOpen: _keyboardOpen,
                      isSending: chat.isSending,
                      isRecording: _isRecording,
                      isRecognizing: _isRecognizing,
                      onKeyboardTap: () {
                        setState(() => _keyboardOpen = !_keyboardOpen);
                      },
                      onVoiceTap: _onVoiceButtonTap,
                      onAttachmentTap: _onAttachmentTap,
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
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
          key: ValueKey('memory-${chat.activeUserId}-$_memoryRefreshToken'),
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
          onBack: () {
            _onPreEntryDataChanged();
            _showView(_AppView.settings);
          },
          onDataChanged: _onPreEntryDataChanged,
        );
    }
  }
}

class _HomeCompanionView extends StatefulWidget {
  const _HomeCompanionView({super.key});

  @override
  State<_HomeCompanionView> createState() => _HomeCompanionViewState();
}

class _HomeCompanionViewState extends State<_HomeCompanionView> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollToBottomVisibility);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollToBottomVisibility)
      ..dispose();
    super.dispose();
  }

  void _updateScrollToBottomVisibility() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    final shouldShow = distanceToBottom > 160;
    if (shouldShow == _showScrollToBottom) return;
    setState(() => _showScrollToBottom = shouldShow);
  }

  Future<void> _scrollToBottom() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _updateScrollToBottomVisibility(),
        );

        return Stack(
          children: [
            ListView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                bottom: _showScrollToBottom ? 76 : 14,
              ),
              children: [
                _ChatCompanionCard(
                  messages: chat.messages,
                  isSending: chat.isSending,
                  onOptionTap: chat.sendOption,
                ),
              ],
            ),
            Positioned(
              right: 14,
              bottom: 18,
              child: IgnorePointer(
                ignoring: !_showScrollToBottom,
                child: AnimatedOpacity(
                  opacity: _showScrollToBottom ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _ScrollToBottomButton(
                    onTap: () => unawaited(_scrollToBottom()),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface1,
      elevation: 2,
      shadowColor: const Color(0x22000000),
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(color: AppTheme.borderHairline, width: 1),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 24,
                color: AppTheme.primaryDeep,
              ),
              SizedBox(width: 4),
              Text(
                '回到底部',
                style: TextStyle(
                  color: AppTheme.primaryDeep,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final isPhoto = message.kind == ChatMessageKind.photo &&
        message.imagePath != null &&
        message.imagePath!.isNotEmpty;
    final isAttachment = message.hasMediaAttachment;

    final Widget content = isPrompt
        ? _PromptCard(message: message, onOptionTap: onOptionTap)
        : isAttachment
            ? _ChatAttachmentBubble(message: message)
            : isPhoto
                ? _ChatPhotoBubble(message: message)
                : _MessageBubble(
                    text: message.content,
                    isUser: message.isUser,
                    isError: message.kind == ChatMessageKind.error,
                  );

    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LetterAvatar(letter: '拾'),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                ChatReadAloudAction(message: message),
              ],
            ),
          ),
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

class _ChatAttachmentBubble extends StatelessWidget {
  const _ChatAttachmentBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isVideo =
        message.attachmentMediaType == ChatAttachmentMediaType.video;
    final isUser = message.isUser;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser ? AppTheme.primarySoft : AppTheme.surface2,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppTheme.radiusBubble),
          topRight: const Radius.circular(AppTheme.radiusBubble),
          bottomLeft: Radius.circular(isUser ? AppTheme.radiusBubble : 6),
          bottomRight: Radius.circular(isUser ? 6 : AppTheme.radiusBubble),
        ),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: TappableMediaThumbnail(
                path: isVideo ? message.videoPath! : message.imagePath!,
                isVideo: isVideo,
                title: message.content.trim().isNotEmpty ? message.content : null,
                child: isVideo
                    ? _MemoryVideoPreview(path: message.videoPath!)
                    : _MemoryPhotoImage(
                        photo: ProfilePhotoModel(
                          id: message.profilePhotoId ?? message.id,
                          ownerUserId: '',
                          filePath: message.imagePath!,
                        ),
                        interactive: false,
                      ),
              ),
            ),
          ),
          if (message.content.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.content,
              style: TextStyle(
                color: isUser ? Colors.white : AppTheme.text,
                fontSize: 19,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatPhotoBubble extends StatelessWidget {
  const _ChatPhotoBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final path = message.imagePath!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radiusBubble),
          border: Border.all(color: AppTheme.borderHairline, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: TappableMediaThumbnail(
                  path: path,
                  isVideo: false,
                  title: message.content.trim().isNotEmpty ? message.content : null,
                  child: _MemoryPhotoImage(
                    photo: ProfilePhotoModel(
                      id: message.profilePhotoId ?? message.id,
                      ownerUserId: '',
                      filePath: path,
                    ),
                    interactive: false,
                  ),
                ),
              ),
            ),
            if (message.content.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message.content,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
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

enum _MemoryViewMode { wall, narration }

class _MemoryBookViewState extends State<_MemoryBookView> {
  late Future<MemoryAlbumDraft> _future;
  final MemoryAlbumRepository _repository = MemoryAlbumRepository();
  late final NarrationPlayer _narrationPlayer;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _segmentKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  DateTime? _lastUserScrollAt;
  _MemoryViewMode _mode = _MemoryViewMode.wall;

  @override
  void initState() {
    super.initState();
    _narrationPlayer = NarrationPlayer()..addListener(_onNarrationChanged);
    _future = _load();
  }

  @override
  void didUpdateWidget(_MemoryBookView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerUserId != widget.ownerUserId) {
      setState(() => _future = _load());
    }
  }

  @override
  void dispose() {
    _narrationPlayer.removeListener(_onNarrationChanged);
    _narrationPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<MemoryAlbumDraft> _load() async {
    final draft = await _repository.buildForUser(widget.ownerUserId);
    if (mounted) {
      _segmentKeys.clear();
      _itemKeys.clear();
      _narrationPlayer.setSegments(draft.album.narration.segments);
    }
    return draft;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MemoryAlbumDraft>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final draft = snapshot.data!;
        final album = draft.album;
        if (!album.hasContent) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 14),
            children: [
              _MemoryAlbumHeader(onRefresh: _refresh),
              const SizedBox(height: 16),
              const _EmptyHint(
                title: '还在等第一段回忆',
                hint: '可以先到「设置 → 数据预录入」里加一张照片，或写下一位家里人',
              ),
            ],
          );
        }
        if (_mode == _MemoryViewMode.narration) {
          return _buildNarrationMode(draft);
        }
        return _PhotoBookView(
          draft: draft,
          onListen: _enterNarrationMode,
          onRefresh: _refresh,
        );
      },
    );
  }

  void _enterNarrationMode() {
    setState(() => _mode = _MemoryViewMode.narration);
  }

  void _exitNarrationMode() {
    _narrationPlayer.stop();
    setState(() => _mode = _MemoryViewMode.wall);
  }

  Widget _buildNarrationMode(MemoryAlbumDraft draft) {
    final album = draft.album;
    final photosById = draft.photosById;
    return Column(
      children: [
        _NarrationModeHeader(onBack: _exitNarrationMode),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 14),
              children: [
                _NarrationStatusPanel(
                  album: album,
                  state: _narrationPlayer.state,
                  currentSegment: _narrationPlayer.currentSegment,
                ),
                _AlbumProfilePanel(
                  card: album.elderProfileCard,
                  narrationPlayer: _narrationPlayer,
                  keyForSegment: _keyForSegment,
                  keyForItem: _keyForItem,
                  onSegmentTap: _playFromSegment,
                ),
                for (final chapter in album.chapters)
                  _AlbumChapterPanel(
                    chapter: chapter,
                    photosById: photosById,
                    narrationPlayer: _narrationPlayer,
                    keyForSegment: _keyForSegment,
                    keyForItem: _keyForItem,
                    onSegmentTap: _playFromSegment,
                  ),
                if (album.familyQuestions.isNotEmpty)
                  _AlbumQuestionsPanel(questions: album.familyQuestions),
              ],
            ),
          ),
        ),
        _NarrationControlBar(
          player: _narrationPlayer,
          onPreviousPage: _previousPage,
          onNextPage: _nextPage,
        ),
      ],
    );
  }

  void _refresh() {
    _narrationPlayer.stop();
    setState(() => _future = _load());
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _lastUserScrollAt = DateTime.now();
    }
    if (notification is UserScrollNotification) {
      _lastUserScrollAt = DateTime.now();
    }
    return false;
  }

  GlobalKey _keyForSegment(String segmentId) {
    return _segmentKeys.putIfAbsent(segmentId, () => GlobalKey());
  }

  GlobalKey _keyForItem(String itemId) {
    return _itemKeys.putIfAbsent(itemId, () => GlobalKey());
  }

  Future<void> _playFromSegment(int index) async {
    _lastUserScrollAt = null;
    await _narrationPlayer.playFromSegment(index);
  }

  void _onNarrationChanged() {
    if (!mounted) return;
    setState(() {});
    _autoScrollToCurrentSegment();
  }

  void _autoScrollToCurrentSegment() {
    final segment = _narrationPlayer.currentSegment;
    if (segment == null) return;
    final lastScroll = _lastUserScrollAt;
    if (lastScroll != null &&
        DateTime.now().difference(lastScroll) < const Duration(seconds: 3)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final segmentContext = _segmentKeys[segment.segmentId]?.currentContext;
      final itemContext = _itemKeys[segment.itemId]?.currentContext;
      final contextToReveal = segmentContext ?? itemContext;
      if (contextToReveal == null) return;
      final renderObject = contextToReveal.findRenderObject();
      final viewport = renderObject == null
          ? null
          : RenderAbstractViewport.maybeOf(renderObject);
      if (renderObject != null &&
          viewport != null &&
          _scrollController.hasClients) {
        final position = _scrollController.position;
        final targetTop = viewport.getOffsetToReveal(renderObject, 0).offset;
        final targetBottom =
            viewport.getOffsetToReveal(renderObject, 1).offset +
                position.viewportDimension;
        final visibleTop = position.pixels;
        final visibleBottom = visibleTop + position.viewportDimension;
        const comfortMargin = 88.0;
        final comfortablyVisible = targetTop >= visibleTop + comfortMargin &&
            targetBottom <= visibleBottom - comfortMargin;
        if (comfortablyVisible) return;
      }
      Scrollable.ensureVisible(
        contextToReveal,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.32,
      );
    });
  }

  Future<void> _previousPage() async {
    final currentPage = _narrationPlayer.state.currentPageIndex;
    final segments = _narrationPlayer.segments;
    for (var i = _narrationPlayer.state.currentSegmentIndex - 1; i >= 0; i--) {
      if (segments[i].pageIndex < currentPage) {
        await _playFromSegment(i);
        return;
      }
    }
    await _playFromSegment(0);
  }

  Future<void> _nextPage() async {
    final currentPage = _narrationPlayer.state.currentPageIndex;
    final segments = _narrationPlayer.segments;
    for (var i = _narrationPlayer.state.currentSegmentIndex + 1;
        i < segments.length;
        i++) {
      if (segments[i].pageIndex > currentPage) {
        await _playFromSegment(i);
        return;
      }
    }
    if (segments.isNotEmpty) {
      await _playFromSegment(segments.length - 1);
    }
  }
}

class _MemoryAlbumHeader extends StatelessWidget {
  const _MemoryAlbumHeader({
    required this.onRefresh,
    this.onListen,
  });

  final VoidCallback onRefresh;
  final VoidCallback? onListen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回忆图鉴',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '一面贴满老照片的墙',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSoft,
                  ),
                ),
              ],
            ),
          ),
          if (onListen != null)
            IconButton(
              tooltip: '听故事',
              onPressed: onListen,
              icon: const Icon(Icons.headphones_rounded),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _NarrationModeHeader extends StatelessWidget {
  const _NarrationModeHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 4, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回相册',
            onPressed: onBack,
            iconSize: 26,
            style: IconButton.styleFrom(
              foregroundColor: AppTheme.primaryDeep,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '听故事模式',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'AI 把这本图鉴整理成一段段故事',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSoft,
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

class _PhotoBookView extends StatefulWidget {
  const _PhotoBookView({
    required this.draft,
    required this.onListen,
    required this.onRefresh,
  });

  final MemoryAlbumDraft draft;
  final VoidCallback onListen;
  final VoidCallback onRefresh;

  @override
  State<_PhotoBookView> createState() => _PhotoBookViewState();
}

class _PhotoBookViewState extends State<_PhotoBookView> {
  static const double _viewportFraction = 0.92;

  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
    _pageController.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    final page = _pageController.page;
    if (page == null) return;
    final next = page.round();
    if (next != _currentIndex) {
      setState(() => _currentIndex = next);
    }
  }

  List<_WallTile> _buildPages() {
    final draft = widget.draft;
    final photos = draft.photos
        .where((p) => p.category != ProfilePhotoCategory.avatar)
        .toList();
    final usedPhotoIds = photos.map((p) => p.id).toSet();
    final events = <_EventCardData>[];
    final photosById = draft.photosById;
    for (final chapter in draft.album.chapters) {
      for (final item in chapter.items) {
        final hasResolvablePhoto = item.photoId.isNotEmpty &&
            (photosById.containsKey(item.photoId) ||
                usedPhotoIds.contains(item.photoId));
        if (hasResolvablePhoto) continue;
        if (item.title.trim().isEmpty && item.content.trim().isEmpty) continue;
        events.add(_EventCardData(
          title: item.title,
          content: item.content,
          chapterTitle: chapter.chapterTitle,
        ));
      }
    }
    return [
      ...photos.map(_WallTile.photo),
      ...events.map(_WallTile.event),
    ];
  }

  void _goPrevious() {
    if (_currentIndex == 0) return;
    _pageController.animateToPage(
      _currentIndex - 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _goNext(int total) {
    if (_currentIndex >= total - 1) return;
    _pageController.animateToPage(
      _currentIndex + 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    if (pages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 14),
        children: [
          _MemoryAlbumHeader(
            onRefresh: widget.onRefresh,
            onListen: widget.onListen,
          ),
          const SizedBox(height: 16),
          const _EmptyHint(
            title: '相册还是空的',
            hint: '到「设置 → 数据预录入」里加一张照片，再来翻看',
          ),
        ],
      );
    }

    return Column(
      children: [
        _BookTopBar(
          currentIndex: _currentIndex,
          total: pages.length,
          onPrevious: _currentIndex > 0 ? _goPrevious : null,
          onNext:
              _currentIndex < pages.length - 1 ? () => _goNext(pages.length) : null,
          onListen: widget.onListen,
          onRefresh: widget.onRefresh,
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final tile = pages[index];
              final pageChild = tile.kind == _WallTileKind.photo
                  ? _BookPhotoPage(
                      photo: tile.photo!,
                      onTap: () => _openPhotoDetail(tile.photo!),
                    )
                  : _BookEventPage(
                      data: tile.event!,
                      onTap: () => _openEventDetail(tile.event!),
                    );
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double signedOffset = 0;
                  if (_pageController.position.haveDimensions) {
                    signedOffset =
                        (_pageController.page ?? index.toDouble()) -
                            index.toDouble();
                  }
                  final absOffset = signedOffset.abs().clamp(0.0, 1.5);
                  final scale = (1.0 - absOffset * 0.10).clamp(0.85, 1.0);
                  final opacity = (1.0 - absOffset * 0.35).clamp(0.55, 1.0);
                  final rotY = signedOffset * 0.18;
                  return Center(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0008)
                        ..rotateY(rotY)
                        ..scaleByDouble(scale, scale, 1.0, 1.0),
                      child: Opacity(opacity: opacity, child: child),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 12),
                  child: pageChild,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openPhotoDetail(ProfilePhotoModel photo) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PhotoDetailSheet(photo: photo),
    );
  }

  void _openEventDetail(_EventCardData data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _EventDetailSheet(data: data),
    );
  }
}

enum _WallTileKind { photo, event }

class _WallTile {
  const _WallTile._({required this.kind, this.photo, this.event});

  factory _WallTile.photo(ProfilePhotoModel photo) =>
      _WallTile._(kind: _WallTileKind.photo, photo: photo);

  factory _WallTile.event(_EventCardData event) =>
      _WallTile._(kind: _WallTileKind.event, event: event);

  final _WallTileKind kind;
  final ProfilePhotoModel? photo;
  final _EventCardData? event;
}

class _EventCardData {
  const _EventCardData({
    required this.title,
    required this.content,
    required this.chapterTitle,
  });

  final String title;
  final String content;
  final String chapterTitle;
}

class _BookTopBar extends StatelessWidget {
  const _BookTopBar({
    required this.currentIndex,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.onListen,
    required this.onRefresh,
  });

  final int currentIndex;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onListen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一页',
            onPressed: onPrevious,
            iconSize: 24,
            icon: const Icon(Icons.chevron_left_rounded),
            style: IconButton.styleFrom(foregroundColor: AppTheme.primaryDeep),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${currentIndex + 1} / $total',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一页',
            onPressed: onNext,
            iconSize: 24,
            icon: const Icon(Icons.chevron_right_rounded),
            style: IconButton.styleFrom(foregroundColor: AppTheme.primaryDeep),
          ),
          IconButton(
            tooltip: '听故事',
            onPressed: onListen,
            icon: const Icon(Icons.headphones_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _BookPhotoPage extends StatelessWidget {
  const _BookPhotoPage({required this.photo, required this.onTap});

  final ProfilePhotoModel photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caption = _captionFor(photo);
    final time = (photo.photoTime ?? '').trim();
    final location = (photo.location ?? '').trim();
    final people = (photo.peopleInvolved ?? '').trim();
    final meta = [time, location].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: AppTheme.surface1,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      elevation: 1,
      shadowColor: const Color(0x14A36B32),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface1,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppTheme.borderHairline, width: 1),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusMedium),
                  child: SizedBox.expand(
                    child: ColoredBox(
                      color: AppTheme.surface0,
                      child: _MemoryPhotoImage(photo: photo),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                caption,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                  height: 1.25,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Text(
                    meta,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent.withValues(alpha: 1.0),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
              if (people.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '里面的人：$people',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _captionFor(ProfilePhotoModel photo) {
    final cap = cleanAlbumCaption(photo.caption);
    if (cap.isNotEmpty) return cap;
    final people = (photo.peopleInvolved ?? '').trim();
    if (people.isNotEmpty) return people;
    final location = (photo.location ?? '').trim();
    if (location.isNotEmpty) return location;
    return '一张老照片';
  }
}

class _BookEventPage extends StatelessWidget {
  const _BookEventPage({required this.data, required this.onTap});

  final _EventCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface2,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      elevation: 1,
      shadowColor: const Color(0x14A36B32),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppTheme.borderHairline, width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDeep.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  data.chapterTitle.isEmpty ? '一段往事' : data.chapterTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDeep,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                data.title.isEmpty ? '一段往事' : data.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    data.content,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.text,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoDetailSheet extends StatelessWidget {
  const _PhotoDetailSheet({required this.photo});

  final ProfilePhotoModel photo;

  @override
  Widget build(BuildContext context) {
    final cap = cleanAlbumCaption(photo.caption);
    final time = (photo.photoTime ?? '').trim();
    final location = (photo.location ?? '').trim();
    final people = (photo.peopleInvolved ?? '').trim();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface1,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLarge),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLarge),
                        child: _MemoryPhotoImage(photo: photo),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (cap.isNotEmpty)
                      Text(
                        cap,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text,
                          height: 1.3,
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (time.isNotEmpty)
                      _DetailRow(label: '时间', value: time),
                    if (location.isNotEmpty)
                      _DetailRow(label: '地点', value: location),
                    if (people.isNotEmpty)
                      _DetailRow(label: '里面的人', value: people),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({required this.data});

  final _EventCardData data;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface1,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLarge),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryDeep.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Text(
                        data.chapterTitle.isEmpty
                            ? '一段往事'
                            : data.chapterTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryDeep,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      data.title.isEmpty ? '一段往事' : data.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      data.content,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.text,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSoft,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppTheme.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrationStatusPanel extends StatelessWidget {
  const _NarrationStatusPanel({
    required this.album,
    required this.state,
    required this.currentSegment,
  });

  final MemoryAlbum album;
  final NarrationState state;
  final NarrationSegment? currentSegment;

  @override
  Widget build(BuildContext context) {
    final chapter = currentSegment?.chapterTitle.trim().isNotEmpty == true
        ? currentSegment!.chapterTitle
        : '尚未开始';
    final item = currentSegment?.itemTitle.trim().isNotEmpty == true
        ? currentSegment!.itemTitle
        : '等待播放';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.albumTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${album.cover.title} · $chapter',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSoft,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textCaption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _NarrationStatusChip(status: state.status),
        ],
      ),
    );
  }
}

class _NarrationStatusChip extends StatelessWidget {
  const _NarrationStatusChip({required this.status});

  final NarrationStatus status;

  String get _label {
    return switch (status) {
      NarrationStatus.idle => '未播放',
      NarrationStatus.playing => '播放中',
      NarrationStatus.paused => '已暂停',
      NarrationStatus.ended => '已读完',
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = status == NarrationStatus.playing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AppTheme.primary : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : AppTheme.primaryDeep,
        ),
      ),
    );
  }
}

class _NarrationSegmentEntry {
  const _NarrationSegmentEntry({
    required this.index,
    required this.segment,
  });

  final int index;
  final NarrationSegment segment;
}

List<_NarrationSegmentEntry> _segmentEntriesForItem(
  NarrationPlayer player,
  String itemId,
) {
  final entries = <_NarrationSegmentEntry>[];
  final segments = player.segments;
  for (var i = 0; i < segments.length; i++) {
    if (segments[i].itemId == itemId) {
      entries.add(_NarrationSegmentEntry(index: i, segment: segments[i]));
    }
  }
  return entries;
}

String _trimNarrationPunctuation(String value) {
  return value.trim().replaceAll(RegExp(r'[。！？!?；;]+$'), '');
}

bool _isTitleSegment(NarrationSegment segment, String title) {
  final cleanTitle = title.trim();
  if (cleanTitle.isEmpty) return false;
  return _trimNarrationPunctuation(segment.text) == cleanTitle;
}

_NarrationSegmentEntry? _titleEntryForItem(
  NarrationPlayer player,
  String itemId,
  String title,
) {
  for (final entry in _segmentEntriesForItem(player, itemId)) {
    if (_isTitleSegment(entry.segment, title)) return entry;
  }
  return null;
}

class _NarrationTitle extends StatelessWidget {
  const _NarrationTitle({
    required this.text,
    required this.style,
    required this.entry,
    required this.state,
    required this.keyForSegment,
    required this.onSegmentTap,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final _NarrationSegmentEntry? entry;
  final NarrationState state;
  final GlobalKey Function(String segmentId) keyForSegment;
  final Future<void> Function(int index) onSegmentTap;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final segmentEntry = entry;
    final active =
        segmentEntry != null && state.currentSegmentIndex == segmentEntry.index;
    final title = Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: style.copyWith(
        color: active ? AppTheme.primaryDeep : style.color,
      ),
    );
    if (segmentEntry == null) return title;
    return InkWell(
      key: keyForSegment(segmentEntry.segment.segmentId),
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      onTap: () => onSegmentTap(segmentEntry.index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppTheme.warningSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (active)
              const Padding(
                padding: EdgeInsets.only(top: 3, right: 6),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: 18,
                  color: AppTheme.primaryDeep,
                ),
              ),
            Expanded(child: title),
          ],
        ),
      ),
    );
  }
}

class _NarrationTextBlock extends StatelessWidget {
  const _NarrationTextBlock({
    required this.itemId,
    required this.title,
    required this.fallbackText,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.onSegmentTap,
    this.textStyle = const TextStyle(
      fontSize: 20,
      height: 1.5,
      color: AppTheme.text,
    ),
  });

  final String itemId;
  final String title;
  final String fallbackText;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final Future<void> Function(int index) onSegmentTap;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final entries = _segmentEntriesForItem(narrationPlayer, itemId)
        .where((entry) => !_isTitleSegment(entry.segment, title))
        .toList();
    if (entries.isEmpty) {
      return Text(fallbackText, style: textStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          _NarrationSentence(
            key: keyForSegment(entry.segment.segmentId),
            text: entry.segment.text,
            active: narrationPlayer.state.currentSegmentIndex == entry.index,
            textStyle: textStyle,
            onTap: () => onSegmentTap(entry.index),
          ),
      ],
    );
  }
}

class _NarrationSentence extends StatelessWidget {
  const _NarrationSentence({
    super.key,
    required this.text,
    required this.active,
    required this.textStyle,
    required this.onTap,
  });

  final String text;
  final bool active;
  final TextStyle textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(8, 7, 10, 8),
          decoration: BoxDecoration(
            color: active ? AppTheme.warningSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: active ? AppTheme.accentSoft : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: AnimatedOpacity(
                  opacity: active ? 1 : 0.28,
                  duration: const Duration(milliseconds: 180),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      active ? Icons.volume_up_rounded : Icons.circle_rounded,
                      size: active ? 17 : 6,
                      color:
                          active ? AppTheme.primaryDeep : AppTheme.textCaption,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: textStyle.copyWith(
                    color: active ? AppTheme.primaryDeep : textStyle.color,
                    fontWeight: active ? FontWeight.w700 : textStyle.fontWeight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NarrationControlBar extends StatelessWidget {
  const _NarrationControlBar({
    required this.player,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final NarrationPlayer player;
  final Future<void> Function() onPreviousPage;
  final Future<void> Function() onNextPage;

  @override
  Widget build(BuildContext context) {
    final state = player.state;
    final currentSegment = player.currentSegment;
    final total = state.totalSegments;
    final hasSegments = total > 0;
    final current = hasSegments
        ? (state.currentSegmentIndex + 1).clamp(1, total).toInt()
        : 0;
    final progress = hasSegments ? current / total : 0.0;
    final isPlaying = state.status == NarrationStatus.playing;
    final chapter = currentSegment?.chapterTitle.trim().isNotEmpty == true
        ? currentSegment!.chapterTitle
        : '听回忆';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: AppTheme.surface1,
          border: Border(
            top: BorderSide(color: AppTheme.borderHairline, width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.errorMessage != null) ...[
              Text(
                state.errorMessage!,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryDeep,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    chapter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  hasSegments ? '第 $current 句 / 共 $total 句' : '暂无可朗读内容',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: AppTheme.borderHairline,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _NarrationIconButton(
                  tooltip: '上一页',
                  icon: Icons.skip_previous_rounded,
                  onPressed:
                      hasSegments ? () => unawaited(onPreviousPage()) : null,
                ),
                _NarrationIconButton(
                  tooltip: '上一句',
                  icon: Icons.keyboard_arrow_left_rounded,
                  onPressed: hasSegments && state.currentSegmentIndex > 0
                      ? () => unawaited(player.previousSegment())
                      : null,
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 54,
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    onPressed: () => _togglePlay(),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : state.status == NarrationStatus.ended
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _NarrationIconButton(
                  tooltip: '下一句',
                  icon: Icons.keyboard_arrow_right_rounded,
                  onPressed:
                      hasSegments && state.currentSegmentIndex < total - 1
                          ? () => unawaited(player.nextSegment())
                          : null,
                ),
                _NarrationIconButton(
                  tooltip: '下一页',
                  icon: Icons.skip_next_rounded,
                  onPressed: hasSegments ? () => unawaited(onNextPage()) : null,
                ),
                const Spacer(),
                PopupMenuButton<double>(
                  tooltip: '语速',
                  initialValue: state.speed,
                  onSelected: player.setSpeed,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 0.8, child: Text('0.8x')),
                    PopupMenuItem(value: 1.0, child: Text('1.0x')),
                    PopupMenuItem(value: 1.25, child: Text('1.25x')),
                  ],
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    child: Text(
                      '${state.speed.toStringAsFixed(state.speed == 1 ? 0 : 2)}x',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryDeep,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _togglePlay() {
    switch (player.state.status) {
      case NarrationStatus.playing:
        player.pause();
        return;
      case NarrationStatus.paused:
        player.resume();
        return;
      case NarrationStatus.ended:
        unawaited(player.playFromSegment(0));
        return;
      case NarrationStatus.idle:
        unawaited(player.play());
        return;
    }
  }
}

class _NarrationIconButton extends StatelessWidget {
  const _NarrationIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 30,
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        foregroundColor: AppTheme.primaryDeep,
        disabledForegroundColor: AppTheme.textCaption,
      ),
    );
  }
}

class _AlbumProfilePanel extends StatelessWidget {
  const _AlbumProfilePanel({
    required this.card,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final ElderProfileCard card;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    if (card.profileItems.isEmpty) return const SizedBox.shrink();
    return _AlbumPanel(
      key: keyForItem('elder_profile_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NarrationTitle(
            text: card.title,
            entry: _titleEntryForItem(
              narrationPlayer,
              'elder_profile_card',
              card.title,
            ),
            state: narrationPlayer.state,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            style: _AlbumSectionTitle.style,
          ),
          const SizedBox(height: 8),
          _NarrationTextBlock(
            itemId: 'elder_profile_card',
            title: card.title,
            fallbackText: card.content,
            narrationPlayer: narrationPlayer,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            textStyle: const TextStyle(
              fontSize: 20,
              height: 1.45,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in card.profileItems)
                _AlbumInfoPill(label: item.label, value: item.value),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlbumChapterPanel extends StatelessWidget {
  const _AlbumChapterPanel({
    required this.chapter,
    required this.photosById,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final MemoryAlbumChapter chapter;
  final Map<String, ProfilePhotoModel> photosById;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    if (chapter.items.isEmpty) return const SizedBox.shrink();
    final introItemId = '${chapter.chapterId}_intro';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            key: keyForItem(introItemId),
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NarrationTitle(
                  text: chapter.chapterTitle,
                  entry: _titleEntryForItem(
                    narrationPlayer,
                    introItemId,
                    chapter.chapterTitle,
                  ),
                  state: narrationPlayer.state,
                  keyForSegment: keyForSegment,
                  onSegmentTap: onSegmentTap,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text,
                    height: 1.2,
                  ),
                ),
                if (chapter.chapterSubtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    chapter.chapterSubtitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSoft,
                    ),
                  ),
                ],
                if (chapter.chapterIntro.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _NarrationTextBlock(
                    itemId: introItemId,
                    title: chapter.chapterTitle,
                    fallbackText: chapter.chapterIntro,
                    narrationPlayer: narrationPlayer,
                    keyForSegment: keyForSegment,
                    onSegmentTap: onSegmentTap,
                    textStyle: const TextStyle(
                      fontSize: 19,
                      height: 1.4,
                      color: AppTheme.text,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final item in chapter.items)
            _AlbumItemPanel(
              item: item,
              photo: photosById[item.photoId],
              narrationPlayer: narrationPlayer,
              keyForSegment: keyForSegment,
              keyForItem: keyForItem,
              onSegmentTap: onSegmentTap,
            ),
        ],
      ),
    );
  }
}

class _AlbumItemPanel extends StatelessWidget {
  const _AlbumItemPanel({
    required this.item,
    required this.photo,
    required this.narrationPlayer,
    required this.keyForSegment,
    required this.keyForItem,
    required this.onSegmentTap,
  });

  final MemoryAlbumItem item;
  final ProfilePhotoModel? photo;
  final NarrationPlayer narrationPlayer;
  final GlobalKey Function(String segmentId) keyForSegment;
  final GlobalKey Function(String itemId) keyForItem;
  final Future<void> Function(int index) onSegmentTap;

  @override
  Widget build(BuildContext context) {
    return _AlbumPanel(
      key: keyForItem(item.itemId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: SizedBox(
                height: 190,
                child: _MemoryPhotoImage(photo: photo!),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AlbumTypeBadge(type: item.itemType),
              const SizedBox(width: 8),
              Expanded(
                child: _NarrationTitle(
                  text: item.title,
                  entry: _titleEntryForItem(
                    narrationPlayer,
                    item.itemId,
                    item.title,
                  ),
                  state: narrationPlayer.state,
                  keyForSegment: keyForSegment,
                  onSegmentTap: onSegmentTap,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _NarrationTextBlock(
            itemId: item.itemId,
            title: item.title,
            fallbackText: item.content,
            narrationPlayer: narrationPlayer,
            keyForSegment: keyForSegment,
            onSegmentTap: onSegmentTap,
            textStyle: const TextStyle(
              fontSize: 20,
              height: 1.5,
              color: AppTheme.text,
            ),
          ),
          if (item.familyQuestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final question in item.familyQuestions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      size: 18,
                      color: AppTheme.primaryDeep,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        question,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.35,
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AlbumQuestionsPanel extends StatelessWidget {
  const _AlbumQuestionsPanel({required this.questions});

  final List<FamilyQuestion> questions;

  @override
  Widget build(BuildContext context) {
    return _AlbumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AlbumSectionTitle('可以再问问家里人'),
          const SizedBox(height: 8),
          for (final question in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.question,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                    ),
                  ),
                  if (question.reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        question.reason,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.35,
                          color: AppTheme.textSoft,
                        ),
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

class _AlbumPanel extends StatelessWidget {
  const _AlbumPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: child,
    );
  }
}

class _AlbumSectionTitle extends StatelessWidget {
  const _AlbumSectionTitle(this.text);

  final String text;

  static const style = TextStyle(
    fontSize: 23,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppTheme.text,
  );

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
    );
  }
}

class _AlbumInfoPill extends StatelessWidget {
  const _AlbumInfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Text(
        '$label：$value',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppTheme.text,
        ),
      ),
    );
  }
}

class _AlbumTypeBadge extends StatelessWidget {
  const _AlbumTypeBadge({required this.type});

  final String type;

  String get _label {
    return switch (type) {
      'photo_card' => '照片',
      'profile_card' => '人物',
      'timeline_card' => '经历',
      'quote_card' => '话语',
      'question_card' => '问题',
      _ => '文字',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MemoryPhotoImage extends StatelessWidget {
  const _MemoryPhotoImage({
    required this.photo,
    this.interactive = true,
  });

  final ProfilePhotoModel photo;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final content = photo.isVideo
        ? _MemoryVideoPreview(path: photo.filePath)
        : _buildImage();
    if (!interactive) return content;
    return TappableMediaThumbnail(
      path: photo.filePath,
      isVideo: photo.isVideo,
      title: photo.caption,
      child: content,
    );
  }

  Widget _buildImage() {
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

class _MemoryVideoPreview extends StatelessWidget {
  const _MemoryVideoPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E2430),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                path.split(RegExp(r'[/\\]')).last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
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
      final timestamp = DateTime.tryParse(row['timestamp'] as String? ?? '');
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
                    color: isEmpty ? AppTheme.textCaption : AppTheme.text,
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
            const _SettingsRowDivider(),
            const ReadAloudSettingsControls(),
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
    required this.pendingAttachment,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final PickedChatAttachment? pendingAttachment;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onSend;

  bool get _canSend {
    if (isSending) return false;
    return controller.text.trim().isNotEmpty || pendingAttachment != null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pendingAttachment != null) ...[
            _PendingAttachmentChip(
              attachment: pendingAttachment!,
              onRemove: onRemoveAttachment,
            ),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !isSending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (_canSend) onSend();
                  },
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.text,
                  ),
                  decoration: InputDecoration(
                    hintText: pendingAttachment == null
                        ? '输入想说的话'
                        : '可以补充说明（可选）',
                    hintStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textCaption,
                    ),
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
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
                  onPressed: _canSend ? onSend : null,
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
        ],
      ),
    );
  }
}

class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final PickedChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isVideo = attachment.isVideo;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderHairline),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 56,
              child: isVideo
                  ? const ColoredBox(
                      color: Color(0xFF1E2430),
                      child: Icon(
                        Icons.videocam_rounded,
                        color: Colors.white70,
                      ),
                    )
                  : attachment.stablePath.startsWith('data:image/')
                      ? Image.network(
                          attachment.stablePath,
                          fit: BoxFit.cover,
                        )
                      : kIsWeb
                          ? const Icon(Icons.image_outlined)
                          : Image.file(
                              File(attachment.stablePath),
                              fit: BoxFit.cover,
                            ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isVideo
                  ? '已选视频：${attachment.originalName}'
                  : '已选照片：${attachment.originalName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppTheme.text,
              ),
            ),
          ),
          IconButton(
            tooltip: '移除',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, color: AppTheme.textSoft),
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
    required this.onAttachmentTap,
  });

  final bool keyboardOpen;
  final bool isSending;
  final bool isRecording;
  final bool isRecognizing;
  final VoidCallback onKeyboardTap;
  final VoidCallback onVoiceTap;
  final VoidCallback onAttachmentTap;

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
            onTap: isSending ? () {} : onAttachmentTap,
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
