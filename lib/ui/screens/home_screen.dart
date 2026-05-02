import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/nearby_person.dart';
import '../../data/models/relation_conflict_record.dart';
import '../../data/local_db/local_database.dart';
import '../../logic/chat_provider.dart';

enum _AppView { home, memory, recent, nearby, settings }

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
  String _speechMode = '自动识别';

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
                        if (chat.pendingRelationConflicts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _RelationConflictBanner(
                            conflict: chat.pendingRelationConflicts.first,
                          ),
                          const SizedBox(height: 8),
                        ],
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
    final chat = context.watch<ChatProvider>();
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
          key: ValueKey('recent-${chat.activeConversationId}'),
          conversationId: chat.activeConversationId,
          onBack: () => _showView(_AppView.home),
        );
      case _AppView.settings:
        return _SettingsView(
          key: ValueKey('settings-${chat.activeUserId}'),
          speechMode: _speechMode,
          networkOnline: _networkOnline,
          activeUserId: chat.activeUserId,
          onBack: () => _showView(_AppView.home),
          onNearbyTap: () => _showView(_AppView.nearby),
          onModeSelected: (value) => setState(() => _speechMode = value),
          onNetworkTap: () => setState(() => _networkOnline = !_networkOnline),
          onAddLocalProfile: _promptAddLocalProfile,
        );
      case _AppView.nearby:
        return _NearbyPeopleView(
          key: ValueKey('nearby-${chat.activeUserId}'),
          ownerUserId: chat.activeUserId,
          onBack: () => _showView(_AppView.settings),
        );
    }
  }

  Future<void> _promptAddLocalProfile() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加使用者'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '称呼或姓名',
            hintText: '例如：李伯伯',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (ok != true || name.isEmpty || !mounted) return;
    await context.read<ChatProvider>().createLocalProfile(name);
    if (mounted) setState(() {});
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
          Text(
            message.title ?? '慢慢想一想',
            style: const TextStyle(
              fontSize: 18,
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
            '拾忆正在认真听您说...',
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '拾忆',
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
                  title: '回忆图鉴',
                  subtitle: '看看珍贵的照片',
                  selected: activeView == _AppView.memory,
                  onTap: onMemoryTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavCard(
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
                title: '慢慢翻看的老相册',
                subtitle: '每一张照片，都可以陪您好好想一想',
              ),
              SizedBox(height: 16),
              _MemoryPhotoCard(
                title: '春天里的自行车',
                year: '1986',
                accent: AppTheme.primary,
              ),
              SizedBox(height: 12),
              _MemoryPhotoCard(
                title: '老家小院的午后',
                year: '1983',
                accent: AppTheme.accent,
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
                          style:
                              TextStyle(fontSize: 16, color: AppTheme.textSoft),
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _BackLine(title: '最近记录', onBack: widget.onBack),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                title: '聊天历史',
                subtitle: '自动从本地数据库读取',
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _confirmClearAll,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('清空全部'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.textSoft),
                  ),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final rows = snapshot.data!;
                  if (rows.isEmpty) {
                    return const Text(
                      '当前还没有聊天历史，先去首页聊几句吧。',
                      style: TextStyle(fontSize: 16, color: AppTheme.textSoft),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      return _ChatHistoryItem(
                        row: rows[index],
                        onDeleted: _refresh,
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
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
        ? '未知时间'
        : '${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} '
            '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    return _RecordItem(
      title: '$role · $timeText',
      description: (row['content'] as String? ?? '').trim().isEmpty
          ? '(空消息)'
          : (row['content'] as String),
      trailing: IconButton(
        tooltip: '删除',
        onPressed: () => _confirmDelete(context),
        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.textSoft),
      ),
    );
  }
}

class _NearbyPeopleView extends StatefulWidget {
  const _NearbyPeopleView({
    super.key,
    required this.ownerUserId,
    required this.onBack,
  });

  final String ownerUserId;
  final VoidCallback onBack;

  @override
  State<_NearbyPeopleView> createState() => _NearbyPeopleViewState();
}

class _NearbyPeopleViewState extends State<_NearbyPeopleView> {
  late Future<List<NearbyPersonModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadNearbyPeople();
  }

  @override
  void didUpdateWidget(_NearbyPeopleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerUserId != widget.ownerUserId) {
      _refresh();
    }
  }

  Future<List<NearbyPersonModel>> _loadNearbyPeople() async {
    final rows =
        await LocalDatabase.getNearbyPeopleForUser(widget.ownerUserId);
    return rows.map(NearbyPersonModel.fromMap).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadNearbyPeople();
    });
  }

  Future<void> _addNearbyPerson() async {
    final nameController = TextEditingController();
    final relationController = TextEditingController();
    final phoneController = TextEditingController();
    bool isEmergency = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加周围人'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '姓名'),
                ),
                TextField(
                  controller: relationController,
                  decoration: const InputDecoration(labelText: '关系'),
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: '联系电话'),
                ),
                SwitchListTile(
                  value: isEmergency,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('紧急联系人'),
                  onChanged: (value) => setState(() => isEmergency = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || nameController.text.trim().isEmpty) return;
    await LocalDatabase.upsertNearbyPerson({
      'id': 'nearby_${DateTime.now().microsecondsSinceEpoch}',
      'owner_user_id': widget.ownerUserId,
      'name': nameController.text.trim(),
      'relation': relationController.text.trim(),
      'phone': phoneController.text.trim(),
      'is_emergency_contact': isEmergency ? 1 : 0,
    });
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _BackLine(title: '周围人信息', onBack: widget.onBack),
        const SizedBox(height: 14),
        _WarmCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.people_alt_rounded,
                title: '附近与亲友联系人',
                subtitle: '本地保存，离线也可查看',
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _addNearbyPerson,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<NearbyPersonModel>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final people = snapshot.data!;
                  if (people.isEmpty) {
                    return const Text(
                      '还没有周围人记录，点击上方“添加”即可开始。',
                      style: TextStyle(fontSize: 16, color: AppTheme.textSoft),
                    );
                  }
                  return Column(
                    children: people
                        .map(
                          (person) => _NearbyPersonTile(
                            person: person,
                            onDelete: () async {
                              await LocalDatabase.removeNearbyPerson(person.id);
                              if (!mounted) return;
                              await _refresh();
                            },
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NearbyPersonTile extends StatelessWidget {
  const _NearbyPersonTile({required this.person, required this.onDelete});

  final NearbyPersonModel person;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${person.name ?? '未命名'}${person.relation == null || person.relation!.isEmpty ? '' : ' · ${person.relation}'}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  person.phone == null || person.phone!.isEmpty
                      ? '未填写联系方式'
                      : person.phone!,
                  style:
                      const TextStyle(fontSize: 15, color: AppTheme.textSoft),
                ),
                if (person.isEmergencyContact)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '紧急联系人',
                      style: TextStyle(
                        color: AppTheme.primaryDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
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
    required this.networkOnline,
    required this.activeUserId,
    required this.onBack,
    required this.onNearbyTap,
    required this.onModeSelected,
    required this.onNetworkTap,
    required this.onAddLocalProfile,
  });

  final String speechMode;
  final bool networkOnline;
  final String activeUserId;
  final VoidCallback onBack;
  final VoidCallback onNearbyTap;
  final ValueChanged<String> onModeSelected;
  final VoidCallback onNetworkTap;
  final VoidCallback onAddLocalProfile;

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
            children: [
              const _SectionTitle(
                icon: Icons.person_rounded,
                title: '使用者与数据划分',
                subtitle: '聊天记录、人物关系与周围人均按当前使用者分开保存',
              ),
              const SizedBox(height: 12),
              _SettingsUserSwitcher(
                activeUserId: activeUserId,
                onAddProfile: onAddLocalProfile,
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
                icon: Icons.shield_rounded,
                title: '本地守护',
                subtitle: '提前录入，后续聊天可继续补充',
              ),
              const SizedBox(height: 16),
              const _SettingsRow(title: '基本信息'),
              const _SettingsRow(title: '家庭照片'),
              const _SettingsRow(title: '重要经历'),
              _SettingsRow(title: '周围人信息', onTap: onNearbyTap),
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
        const SizedBox(height: 14),
        FutureBuilder<String>(
          future: LocalDatabase.getDatabasePathForDebug(),
          builder: (context, snapshot) {
            final path = snapshot.data ?? '读取中...';
            return _WarmCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(
                    icon: Icons.storage_rounded,
                    title: '本地数据库文件',
                    subtitle: '文件名 bluecare.db，可用下方完整路径在资源管理器中打开',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    LocalDatabase.storageHint(),
                    style:
                        const TextStyle(fontSize: 14, color: AppTheme.textSoft),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    path,
                    style: const TextStyle(fontSize: 14, color: AppTheme.text),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RelationConflictBanner extends StatelessWidget {
  const _RelationConflictBanner({required this.conflict});

  final RelationConflictRecord conflict;

  @override
  Widget build(BuildContext context) {
    return _WarmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.primaryDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '人物信息与聊天内容不一致',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${conflict.personName} · ${conflict.fieldLabel}',
            style: const TextStyle(fontSize: 15, color: AppTheme.textSoft),
          ),
          const SizedBox(height: 6),
          Text(
            '原有：${conflict.oldValue ?? '（空）'}\n新提到：${conflict.newValue ?? '（空）'}',
            style: const TextStyle(fontSize: 15, height: 1.45, color: AppTheme.text),
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
    );
  }
}

class _SettingsUserSwitcher extends StatelessWidget {
  const _SettingsUserSwitcher({
    required this.activeUserId,
    required this.onAddProfile,
  });

  final String activeUserId;
  final VoidCallback onAddProfile;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: LocalDatabase.listUsers(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Text(
            '暂无使用者记录',
            style: TextStyle(fontSize: 16, color: AppTheme.textSoft),
          );
        }
        final ids = users.map((u) => u['id'] as String).toSet();
        final value =
            ids.contains(activeUserId) ? activeUserId : users.first['id'] as String;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: value,
              decoration: const InputDecoration(
                labelText: '当前使用者',
                filled: true,
                fillColor: Colors.white,
              ),
              items: users.map((u) {
                final id = u['id'] as String;
                final name = (u['name'] as String?)?.trim();
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(name == null || name.isEmpty ? id : name),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  context.read<ChatProvider>().setActiveUserId(v);
                }
              },
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onAddProfile,
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('添加另一位使用者'),
            ),
          ],
        );
      },
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                isSending ? '等待' : '发送',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
            child: TextButton(
              onPressed: onKeyboardTap,
              style: TextButton.styleFrom(
                backgroundColor:
                    keyboardOpen ? AppTheme.successSoft : Colors.white,
                foregroundColor:
                    keyboardOpen ? AppTheme.primaryDeep : AppTheme.textSoft,
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
                side: const BorderSide(color: AppTheme.border),
              ),
              child: const Text('键盘'),
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
                    Text(
                      isSending ? '正在回应' : '按住这里说话',
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
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
            height: 62,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryDeep,
                textStyle:
                    const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
                side: const BorderSide(color: AppTheme.border),
              ),
              child: const Text('+'),
            ),
          ),
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
      child: const Text(
        '离线陪伴 · 本地守护',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppTheme.primaryDeep,
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

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
    this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData? icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
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
        ],
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
  });

  final String title;
  final String year;
  final Color accent;

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
            child: Center(
              child: Text(
                year,
                style: TextStyle(
                  color: accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
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
                  style: TextStyle(
                      fontSize: 15, height: 1.35, color: AppTheme.textSoft),
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
      alignment: Alignment.center,
      child: const Text(
        '照片',
        style: TextStyle(
          color: AppTheme.primaryDeep,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
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
          backgroundColor:
              label == '再想想' ? AppTheme.accentSoft : AppTheme.successSoft,
          foregroundColor:
              label == '再想想' ? AppTheme.text : AppTheme.primaryDeep,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    required this.title,
    required this.description,
    this.trailing,
  });

  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

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
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          border: Border.all(
              color: online ? const Color(0xFFD4EEE9) : AppTheme.border),
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
    this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      backgroundColor: AppTheme.cardWhite,
      foregroundColor: AppTheme.text,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.border),
      ),
    );

    return SizedBox(
      height: 50,
      child: icon == null
          ? TextButton(
              onPressed: onTap,
              style: style,
              child: Text(label),
            )
          : TextButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 20),
              label: Text(label),
              style: style,
            ),
    );
  }
}
