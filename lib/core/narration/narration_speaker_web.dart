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
      ..rate = (rate.clamp(0.6, 1.6) * 0.94).clamp(0.56, 1.5).toDouble()
      ..pitch = 0.96
      ..volume = 1.0;
    final voice = _pickGentleChineseVoice(synth);
    if (voice != null) {
      utterance.voice = voice;
    }

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

  html.SpeechSynthesisVoice? _pickGentleChineseVoice(
    html.SpeechSynthesis synth,
  ) {
    final voices = synth.getVoices();
    if (voices.isEmpty) return null;
    final chineseVoices = voices
        .where((voice) => (voice.lang ?? '').toLowerCase().startsWith('zh'))
        .toList();
    if (chineseVoices.isEmpty) return null;

    int score(html.SpeechSynthesisVoice voice) {
      final name = '${voice.name} ${voice.voiceUri}'.toLowerCase();
      var value = 0;
      if (name.contains('xiaoxiao') || name.contains('晓晓')) value += 12;
      if (name.contains('yaoyao') || name.contains('瑶瑶')) value += 10;
      if (name.contains('huihui') || name.contains('huihui')) value += 8;
      if (name.contains('female') || name.contains('女')) value += 6;
      if ((voice.lang ?? '').toLowerCase() == 'zh-cn') value += 4;
      if (voice.localService == true) value += 2;
      return value;
    }

    chineseVoices.sort((a, b) => score(b).compareTo(score(a)));
    return chineseVoices.first;
  }
}
