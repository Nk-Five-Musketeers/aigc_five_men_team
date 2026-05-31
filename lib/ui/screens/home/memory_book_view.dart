part of '../home_screen.dart';

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
  late Future<MemoryAlbumDraft> _future;
  final MemoryAlbumRepository _repository = MemoryAlbumRepository();
  late final NarrationPlayer _narrationPlayer;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _segmentKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  DateTime? _lastUserScrollAt;

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
        final photosById = draft.photosById;
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
        return Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 14),
                  children: [
                    _MemoryAlbumHeader(onRefresh: _refresh),
                    _NarrationStatusPanel(
                      album: album,
                      state: _narrationPlayer.state,
                      currentSegment: _narrationPlayer.currentSegment,
                    ),
                    _AlbumCoverPanel(
                      album: album,
                      photo: photosById[album.cover.recommendedCoverPhotoId],
                      narrationPlayer: _narrationPlayer,
                      keyForSegment: _keyForSegment,
                      keyForItem: _keyForItem,
                      onSegmentTap: _playFromSegment,
                    ),
                    _AlbumTextPanel(
                      text: album.opening,
                      itemId: 'opening',
                      narrationPlayer: _narrationPlayer,
                      keyForSegment: _keyForSegment,
                      keyForItem: _keyForItem,
                      onSegmentTap: _playFromSegment,
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
                    if (album.timeline.isNotEmpty)
                      _AlbumTimelinePanel(entries: album.timeline),
                    if (album.familyQuestions.isNotEmpty)
                      _AlbumQuestionsPanel(questions: album.familyQuestions),
                    _AlbumNotesPanel(notes: album.notes),
                    _AlbumTextPanel(
                      text: album.ending,
                      itemId: 'ending',
                      narrationPlayer: _narrationPlayer,
                      keyForSegment: _keyForSegment,
                      keyForItem: _keyForItem,
                      onSegmentTap: _playFromSegment,
                    ),
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
      },
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
  const _MemoryAlbumHeader({required this.onRefresh});

  final VoidCallback onRefresh;

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
                  '把人、事和照片慢慢放进一本册子',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSoft,
                  ),
                ),
              ],
            ),
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
