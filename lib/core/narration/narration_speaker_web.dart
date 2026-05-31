// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

class NarrationSpeaker {
  bool get isSupported => html.window.speechSynthesis != null;
  bool get canResumePausedUtterance => true;

  Future<void> speak(String text, {required double rate}) {
    final synth = html.window.speechSynthesis;
    if (synth == null) {
      return Future<void>.error(
        UnsupportedError('当前浏览器暂不支持语音朗读。'),
      );
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future<void>.value();

    final completer = Completer<void>();
    final utterance = html.SpeechSynthesisUtterance(trimmed)
      ..lang = 'zh-CN'
      ..rate = rate.clamp(0.6, 1.6).toDouble()
      ..pitch = 1.0
      ..volume = 1.0;

    late StreamSubscription<html.Event> endSub;
    late StreamSubscription<html.Event> errorSub;
    void complete() {
      endSub.cancel();
      errorSub.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    endSub = utterance.onEnd.listen((_) => complete());
    errorSub = utterance.onError.listen((_) {
      endSub.cancel();
      errorSub.cancel();
      if (!completer.isCompleted) {
        completer.completeError(StateError('朗读这一句时遇到问题。'));
      }
    });

    synth.cancel();
    synth.speak(utterance);
    return completer.future;
  }

  void pause() {
    html.window.speechSynthesis?.pause();
  }

  void resume() {
    html.window.speechSynthesis?.resume();
  }

  void stop() {
    html.window.speechSynthesis?.cancel();
  }

  void dispose() {
    stop();
  }
}
