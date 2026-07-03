part of '../home_screen.dart';

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
                        onSend: _sendTypedMessage,
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
