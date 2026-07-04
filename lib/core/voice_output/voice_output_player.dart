import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

abstract class VoiceOutputPlayer {
  Stream<void> get onComplete;

  Future<void> playUrl(String url, {String? mimeType});

  Future<void> play(Uint8List wavBytes);

  Future<void> stop();

  Future<void> dispose();
}

class AudioplayersVoiceOutputPlayer implements VoiceOutputPlayer {
  AudioplayersVoiceOutputPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> playUrl(String url, {String? mimeType}) async {
    await _player.play(
      UrlSource(url, mimeType: mimeType),
    );
  }

  @override
  Future<void> play(Uint8List wavBytes) async {
    await _player.play(
      BytesSource(wavBytes, mimeType: 'audio/wav'),
    );
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
