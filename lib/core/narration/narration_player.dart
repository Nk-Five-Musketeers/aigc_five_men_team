import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/memory_album.dart';
import 'narration_speaker.dart';

enum NarrationStatus { idle, playing, paused, ended }

class NarrationState {
  const NarrationState({
    required this.status,
    required this.currentSegmentIndex,
    required this.currentChapterId,
    required this.currentItemId,
    required this.currentPageIndex,
    required this.speed,
    required this.totalSegments,
    this.errorMessage,
  });

  final NarrationStatus status;
  final int currentSegmentIndex;
  final String currentChapterId;
  final String currentItemId;
  final int currentPageIndex;
  final double speed;
  final int totalSegments;
  final String? errorMessage;

  NarrationState copyWith({
    NarrationStatus? status,
    int? currentSegmentIndex,
    String? currentChapterId,
    String? currentItemId,
    int? currentPageIndex,
    double? speed,
    int? totalSegments,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NarrationState(
      status: status ?? this.status,
      currentSegmentIndex: currentSegmentIndex ?? this.currentSegmentIndex,
      currentChapterId: currentChapterId ?? this.currentChapterId,
      currentItemId: currentItemId ?? this.currentItemId,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      speed: speed ?? this.speed,
      totalSegments: totalSegments ?? this.totalSegments,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  static const empty = NarrationState(
    status: NarrationStatus.idle,
    currentSegmentIndex: 0,
    currentChapterId: '',
    currentItemId: '',
    currentPageIndex: 0,
    speed: 1.0,
    totalSegments: 0,
  );
}

class NarrationPlayer extends ChangeNotifier {
  NarrationPlayer({NarrationSpeaker? speaker})
      : _speaker = speaker ?? NarrationSpeaker();

  final NarrationSpeaker _speaker;
  List<NarrationSegment> _segments = const <NarrationSegment>[];
  NarrationState _state = NarrationState.empty;
  int _playToken = 0;

  NarrationState get state => _state;
  List<NarrationSegment> get segments => List.unmodifiable(_segments);
  bool get isSupported => _speaker.isSupported;

  NarrationSegment? get currentSegment {
    if (_segments.isEmpty) return null;
    final index =
        _state.currentSegmentIndex.clamp(0, _segments.length - 1).toInt();
    return _segments[index];
  }

  void setSegments(List<NarrationSegment> segments) {
    stop();
    _segments = List<NarrationSegment>.unmodifiable(segments);
    _applySegment(index: 0, status: NarrationStatus.idle, clearError: true);
  }

  Future<void> play() {
    if (_segments.isEmpty) {
      _state = _state.copyWith(
        status: NarrationStatus.idle,
        errorMessage: '现在还没有可以朗读的内容。',
      );
      notifyListeners();
      return Future<void>.value();
    }
    final start =
        _state.status == NarrationStatus.ended ? 0 : _state.currentSegmentIndex;
    return playFromSegment(start);
  }

  void pause() {
    if (_state.status != NarrationStatus.playing) return;
    _state = _state.copyWith(status: NarrationStatus.paused);
    notifyListeners();
    _speaker.pause();
  }

  void resume() {
    if (_state.status != NarrationStatus.paused) return;
    if (!isSupported) {
      _state = _state.copyWith(
        status: NarrationStatus.idle,
        errorMessage: '当前设备暂不支持直接朗读。可以在 Windows 或浏览器里使用听回忆。',
      );
      notifyListeners();
      return;
    }
    if (!_speaker.canResumePausedUtterance) {
      unawaited(playFromSegment(_state.currentSegmentIndex));
      return;
    }
    _speaker.resume();
    _state = _state.copyWith(status: NarrationStatus.playing, clearError: true);
    notifyListeners();
  }

  void stop() {
    _playToken++;
    _speaker.stop();
    _state = _state.copyWith(status: NarrationStatus.idle, clearError: true);
    notifyListeners();
  }

  Future<void> playFromSegment(int index) {
    if (_segments.isEmpty) return play();
    if (!isSupported) {
      _state = _state.copyWith(
        status: NarrationStatus.idle,
        errorMessage: '当前设备暂不支持直接朗读。可以在浏览器里打开后使用听回忆。',
      );
      notifyListeners();
      return Future<void>.value();
    }
    final clamped = index.clamp(0, _segments.length - 1).toInt();
    _playToken++;
    final token = _playToken;
    _speaker.stop();
    _applySegment(
      index: clamped,
      status: NarrationStatus.playing,
      clearError: true,
    );
    return _speakCurrent(token);
  }

  Future<void> nextSegment() {
    if (_segments.isEmpty) return Future<void>.value();
    final next =
        (_state.currentSegmentIndex + 1).clamp(0, _segments.length - 1).toInt();
    return playFromSegment(next);
  }

  Future<void> previousSegment() {
    if (_segments.isEmpty) return Future<void>.value();
    final previous =
        (_state.currentSegmentIndex - 1).clamp(0, _segments.length - 1).toInt();
    return playFromSegment(previous);
  }

  void setSpeed(double speed) {
    final nextSpeed = speed.clamp(0.6, 1.6).toDouble();
    if (nextSpeed == _state.speed) return;
    final wasPlaying = _state.status == NarrationStatus.playing;
    _state = _state.copyWith(speed: nextSpeed, clearError: true);
    notifyListeners();
    if (wasPlaying) {
      playFromSegment(_state.currentSegmentIndex);
    }
  }

  Future<void> _speakCurrent(int token) async {
    final segment = currentSegment;
    if (segment == null) return;
    try {
      await _speaker.speak(segment.text, rate: _state.speed);
      if (token != _playToken || _state.status != NarrationStatus.playing) {
        return;
      }
      if (_state.currentSegmentIndex >= _segments.length - 1) {
        _state = _state.copyWith(status: NarrationStatus.ended);
        notifyListeners();
        return;
      }
      _applySegment(
        index: _state.currentSegmentIndex + 1,
        status: NarrationStatus.playing,
        clearError: true,
      );
      await _speakCurrent(token);
    } catch (_) {
      if (token != _playToken) return;
      _state = _state.copyWith(
        status: NarrationStatus.paused,
        errorMessage: '朗读这一句时遇到问题，可以稍后再试。',
      );
      notifyListeners();
    }
  }

  void _applySegment({
    required int index,
    required NarrationStatus status,
    bool clearError = false,
  }) {
    final segment = _segments.isEmpty
        ? null
        : _segments[index.clamp(0, _segments.length - 1).toInt()];
    _state = _state.copyWith(
      status: status,
      currentSegmentIndex: index,
      currentChapterId: segment?.chapterId ?? '',
      currentItemId: segment?.itemId ?? '',
      currentPageIndex: segment?.pageIndex ?? 0,
      totalSegments: _segments.length,
      clearError: clearError,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _speaker.dispose();
    super.dispose();
  }
}
