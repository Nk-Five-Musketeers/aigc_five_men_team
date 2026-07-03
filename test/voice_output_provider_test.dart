import 'dart:typed_data';

import 'package:aigc_five_men_team/core/voice_output/tts_repository.dart';
import 'package:aigc_five_men_team/core/voice_output/voice_output_player.dart';
import 'package:aigc_five_men_team/core/voice_output/voice_output_settings_store.dart';
import 'package:aigc_five_men_team/logic/voice_output_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _SynthesisCall {
  _SynthesisCall({
    required this.text,
    required this.voice,
    required this.speed,
    required this.volume,
  });

  final String text;
  final String voice;
  final int speed;
  final int volume;
}

class _FakeSynthesizer implements TtsSynthesizer {
  final List<_SynthesisCall> calls = [];
  Uint8List bytes = Uint8List.fromList([1, 2, 3, 4]);

  @override
  Future<Uint8List> synthesize({
    required String text,
    String voice = 'xiaofu',
    int speed = 50,
    int volume = 50,
  }) async {
    calls.add(
      _SynthesisCall(
        text: text,
        voice: voice,
        speed: speed,
        volume: volume,
      ),
    );
    return bytes;
  }
}

class _FakePlayer implements VoiceOutputPlayer {
  final Stream<void> _completion = const Stream<void>.empty();
  final List<String> events = [];

  @override
  Stream<void> get onComplete => _completion;

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }

  @override
  Future<void> play(Uint8List wavBytes) async {
    events.add('play:${wavBytes.join(',')}');
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }
}

class _FakeSettingsStore implements VoiceOutputSettingsStore {
  _FakeSettingsStore({this.speed, this.volume});

  int? speed;
  int? volume;

  @override
  Future<int?> loadSpeed() async => speed;

  @override
  Future<int?> loadVolume() async => volume;

  @override
  Future<void> saveSpeed(int value) async {
    speed = value;
  }

  @override
  Future<void> saveVolume(int value) async {
    volume = value;
  }
}

void main() {
  test('uses wanqing and persisted speed volume when reading a reply',
      () async {
    final synthesizer = _FakeSynthesizer();
    final player = _FakePlayer();
    final provider = VoiceOutputProvider(
      synthesizer: synthesizer,
      player: player,
      settingsStore: _FakeSettingsStore(speed: 42, volume: 63),
    );

    await provider.loadSettings();
    await provider.toggleReadAloud(messageId: 'reply-1', text: '您好');

    expect(provider.playingMessageId, 'reply-1');
    expect(synthesizer.calls, hasLength(1));
    expect(synthesizer.calls.single.voice, 'wanqing');
    expect(synthesizer.calls.single.speed, 42);
    expect(synthesizer.calls.single.volume, 63);
    provider.dispose();
  });

  test('tapping the playing reply stops playback', () async {
    final player = _FakePlayer();
    final provider = VoiceOutputProvider(
      synthesizer: _FakeSynthesizer(),
      player: player,
      settingsStore: _FakeSettingsStore(),
    );

    await provider.toggleReadAloud(messageId: 'reply-1', text: '您好');
    await provider.toggleReadAloud(messageId: 'reply-1', text: '您好');

    expect(provider.playingMessageId, isNull);
    expect(player.events, contains('stop'));
    provider.dispose();
  });

  test('switching reply stops previous playback first', () async {
    final player = _FakePlayer();
    final provider = VoiceOutputProvider(
      synthesizer: _FakeSynthesizer(),
      player: player,
      settingsStore: _FakeSettingsStore(),
    );

    await provider.toggleReadAloud(messageId: 'reply-1', text: '第一句话');
    await provider.toggleReadAloud(messageId: 'reply-2', text: '第二句话');

    expect(provider.playingMessageId, 'reply-2');
    expect(player.events, [
      'play:1,2,3,4',
      'stop',
      'play:1,2,3,4',
    ]);
    provider.dispose();
  });

  test('reuses cached wav bytes for the same text and settings', () async {
    final synthesizer = _FakeSynthesizer();
    final provider = VoiceOutputProvider(
      synthesizer: synthesizer,
      player: _FakePlayer(),
      settingsStore: _FakeSettingsStore(),
    );

    await provider.toggleReadAloud(messageId: 'reply-1', text: '您好');
    await provider.toggleReadAloud(messageId: 'reply-1', text: '您好');
    await provider.toggleReadAloud(messageId: 'reply-1', text: '您好');

    expect(synthesizer.calls, hasLength(1));
    provider.dispose();
  });

  test('loads and persists speed and volume settings', () async {
    final store = _FakeSettingsStore(speed: 41, volume: 62);
    final provider = VoiceOutputProvider(
      synthesizer: _FakeSynthesizer(),
      player: _FakePlayer(),
      settingsStore: store,
    );

    await provider.loadSettings();
    await provider.setSpeed(54);
    await provider.setVolume(76);

    expect(provider.speed, 54);
    expect(provider.volume, 76);
    expect(store.speed, 54);
    expect(store.volume, 76);
    provider.dispose();
  });
}
