import 'dart:async';

class NarrationSpeaker {
  bool get isSupported => false;
  bool get canResumePausedUtterance => false;

  Future<void> speak(String text, {required double rate}) {
    return Future<void>.error(
      UnsupportedError('当前设备暂不支持直接朗读，请在浏览器中使用听回忆模式。'),
    );
  }

  void pause() {}

  void resume() {}

  void stop() {}

  void dispose() {
    stop();
  }
}
