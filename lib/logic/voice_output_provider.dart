import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/voice_output/tts_repository.dart';
import '../core/voice_output/voice_output_player.dart';
import '../core/voice_output/voice_output_settings_store.dart';

class VoiceOutputProvider extends ChangeNotifier {
  VoiceOutputProvider({
    TtsSynthesizer? synthesizer,
    VoiceOutputPlayer? player,
    VoiceOutputSettingsStore? settingsStore,
    bool preferStreaming = true,
  })  : _synthesizer = synthesizer ?? TtsRepository(),
        _player = player ?? AudioplayersVoiceOutputPlayer(),
        _settingsStore =
            settingsStore ?? SharedPreferencesVoiceOutputSettingsStore(),
        _preferStreaming = preferStreaming {
    _completionSubscription = _player.onComplete.listen((_) {
      if (_playingMessageId == null) return;
      _playingMessageId = null;
      notifyListeners();
    });
  }

  static const String defaultVoice = 'wanqing';

  final TtsSynthesizer _synthesizer;
  final VoiceOutputPlayer _player;
  final VoiceOutputSettingsStore _settingsStore;
  final bool _preferStreaming;
  final Map<String, Uint8List> _wavCache = <String, Uint8List>{};

  late final StreamSubscription<void> _completionSubscription;
  String? _loadingMessageId;
  String? _playingMessageId;
  int _operationId = 0;
  int _speed = 50;
  int _volume = 50;

  String? get loadingMessageId => _loadingMessageId;

  String? get playingMessageId => _playingMessageId;

  int get speed => _speed;

  int get volume => _volume;

  Future<void> loadSettings() async {
    final values = await Future.wait<int?>([
      _settingsStore.loadSpeed(),
      _settingsStore.loadVolume(),
    ]);
    _speed = (values[0] ?? 50).clamp(0, 100);
    _volume = (values[1] ?? 50).clamp(1, 100);
    notifyListeners();
  }

  Future<void> setSpeed(int value) async {
    _speed = value.clamp(0, 100);
    notifyListeners();
    await _settingsStore.saveSpeed(_speed);
  }

  Future<void> setVolume(int value) async {
    _volume = value.clamp(1, 100);
    notifyListeners();
    await _settingsStore.saveVolume(_volume);
  }

  Future<void> toggleReadAloud({
    required String messageId,
    required String text,
  }) async {
    if (_loadingMessageId == messageId || _playingMessageId == messageId) {
      await stop();
      return;
    }
    if (_loadingMessageId != null || _playingMessageId != null) {
      await stop();
    }

    final operationId = ++_operationId;
    _loadingMessageId = messageId;
    notifyListeners();
    try {
      if (_preferStreaming) {
        final uri = _synthesizer.streamUri(
          text: text,
          voice: defaultVoice,
          speed: _speed,
          volume: _volume,
        );
        try {
          await _player.playUrl(uri.toString(), mimeType: 'audio/wav');
        } catch (_) {
          await _playCachedBytes(text);
        }
      } else {
        await _playCachedBytes(text);
      }
      if (operationId != _operationId) {
        await _player.stop();
        return;
      }
      _loadingMessageId = null;
      _playingMessageId = messageId;
      notifyListeners();
    } catch (_) {
      if (operationId == _operationId) {
        _loadingMessageId = null;
        _playingMessageId = null;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> _playCachedBytes(String text) async {
    final cacheKey = '$defaultVoice|$_speed|$_volume|$text';
    final bytes = _wavCache[cacheKey] ??
        await _synthesizer.synthesize(
          text: text,
          voice: defaultVoice,
          speed: _speed,
          volume: _volume,
        );
    _wavCache[cacheKey] = bytes;
    await _player.play(bytes);
  }

  Future<void> stop() async {
    _operationId++;
    final changed = _loadingMessageId != null || _playingMessageId != null;
    _loadingMessageId = null;
    _playingMessageId = null;
    await _player.stop();
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_completionSubscription.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }
}
