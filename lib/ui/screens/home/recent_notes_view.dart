part of '../home_screen.dart';

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
