part of '../home_screen.dart';

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
