part of '../home_screen.dart';

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

    final Widget content = isPrompt
        ? _PromptCard(message: message, onOptionTap: onOptionTap)
        : isPhoto
            ? _ChatPhotoBubble(message: message)
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
                child: _MemoryPhotoImage(
                  photo: ProfilePhotoModel(
                    id: message.profilePhotoId ?? message.id,
                    ownerUserId: '',
                    filePath: path,
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
