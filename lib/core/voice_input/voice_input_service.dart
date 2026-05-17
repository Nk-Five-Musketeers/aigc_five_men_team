import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'vivo_asr_input_service.dart';
import 'voice_input_exceptions.dart';

/// 语音识别统一入口：默认 vivo ASR（经本地代理），失败回退系统 [speech_to_text]。
///
/// 模块内文件：
/// - [VivoAsrInputService] 录音 + 上传
/// - [AsrRepository] 调用 `/api/asr/transcribe`
/// - 本类 系统听写与引擎调度
class VoiceInputService {
  VoiceInputService._();

  static final SpeechToText _speech = SpeechToText();

  static Completer<String>? _sessionResult;
  static bool _stopRequested = false;
  static bool _endedByUserStopButton = false;

  static String _sessionLine = '';
  static bool _openListenSession = false;
  static bool _sessionUsesVivo = false;

  static List<LocaleName>? _cachedLocales;
  static LocaleName? _cachedSystemLocale;

  static const Duration initTimeout = Duration(seconds: 12);
  static const Duration listenForMax = Duration(minutes: 5);
  static const Duration sessionHardTimeout = Duration(seconds: 310);
  static const Duration stopFromUserTimeout = Duration(seconds: 5);
  static const Duration listenStartTimeout = Duration(seconds: 5);

  static bool get isEngineAvailable => _speech.isAvailable;

  static Future<void> prepareEngine() async {
    await Future.wait<void>([
      VivoAsrInputService.prepareEngine(),
      () async {
        try {
          await _ensureInitialized();
          await _ensureLocaleCaches();
        } catch (_) {}
      }(),
    ]);
  }

  static Future<void> _ensureLocaleCaches() async {
    if (!_speech.isAvailable) return;
    try {
      _cachedLocales ??= await _speech.locales().timeout(
        const Duration(seconds: 2),
        onTimeout: () => <LocaleName>[],
      );
    } catch (_) {
      _cachedLocales = _cachedLocales ?? <LocaleName>[];
    }
    if (_cachedSystemLocale == null) {
      try {
        _cachedSystemLocale = await _speech.systemLocale();
      } catch (_) {}
    }
  }

  static bool consumeEndedByUserStop() {
    if (_sessionUsesVivo) {
      return VivoAsrInputService.consumeEndedByUserStop();
    }
    final v = _endedByUserStopButton;
    _endedByUserStopButton = false;
    return v;
  }

  static void _resetTranscript() {
    _sessionLine = '';
  }

  static int _longestSuffixPrefixOverlap(String a, String b) {
    final max = a.length < b.length ? a.length : b.length;
    for (var len = max; len > 0; len--) {
      if (a.endsWith(b.substring(0, len))) return len;
    }
    return 0;
  }

  static const _sentenceEndChars = '。！？；…．.!?\n';

  static bool _endsWithSentenceBoundary(String s) {
    if (s.isEmpty) return false;
    return _sentenceEndChars.contains(s[s.length - 1]);
  }

  static bool _looksMostlyLatin(String s) {
    if (s.isEmpty) return false;
    var asciiLetters = 0;
    var nonAscii = 0;
    for (final code in s.codeUnits) {
      if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
        asciiLetters++;
      } else if (code > 127) {
        nonAscii++;
      }
    }
    return asciiLetters >= 3 && nonAscii < asciiLetters;
  }

  static String _joinDisjointSegments(String prev, String next) {
    if (prev.isEmpty) return next;
    if (next.isEmpty) return prev;
    if (_endsWithSentenceBoundary(prev)) return '$prev$next';
    if (_looksMostlyLatin(prev) || _looksMostlyLatin(next)) {
      return '$prev $next';
    }
    return '$prev，$next';
  }

  static void _mergeRecognizedFragment(SpeechRecognitionResult result) {
    var w = result.recognizedWords.trim();
    if (w.isEmpty) return;
    if (_sessionLine.isEmpty) {
      _sessionLine = w;
      return;
    }
    if (w.startsWith(_sessionLine)) {
      _sessionLine = w;
      return;
    }
    if (_sessionLine.startsWith(w)) {
      return;
    }
    final overlap = _longestSuffixPrefixOverlap(_sessionLine, w);
    if (overlap > 0) {
      _sessionLine = _sessionLine + w.substring(overlap);
      return;
    }
    if (result.finalResult) {
      _sessionLine = _joinDisjointSegments(_sessionLine, w);
      return;
    }
    if (w.length >= _sessionLine.length) {
      _sessionLine = w;
    }
  }

  static String _bestSessionText() {
    final a = _sessionLine.trim();
    final b = _speech.lastRecognizedWords.trim();
    if (a.length >= b.length) return a;
    return b;
  }

  static void _finishSession([String? explicit]) {
    final ex = explicit?.trim() ?? '';
    final text = ex.isNotEmpty ? ex : _bestSessionText();
    final c = _sessionResult;
    if (c != null && !c.isCompleted) {
      c.complete(text);
    }
    _sessionResult = null;
  }

  static void _onStatus(String status) {
    debugPrint('[VoiceInput] status=$status');
    if (status != SpeechToText.doneStatus) return;

    if (!_openListenSession) {
      _finishSession();
      return;
    }
    if (_endedByUserStopButton || _speech.isNotListening) {
      _finishSession();
      return;
    }
    debugPrint('[VoiceInput] ignore spurious done while listening (single session)');
  }

  static void _onResult(SpeechRecognitionResult result) {
    _mergeRecognizedFragment(result);
    final preview = _sessionLine.length > 48
        ? '${_sessionLine.substring(0, 48)}…'
        : _sessionLine;
    debugPrint(
      '[VoiceInput] onResult final=${result.finalResult} len=${_sessionLine.length} `$preview`',
    );
  }

  static void _onError(SpeechRecognitionError e) {
    debugPrint('[VoiceInput] error=${e.errorMsg} permanent=${e.permanent}');
    if (e.permanent) {
      _finishSession();
    }
  }

  static Future<void> _ensureInitialized() async {
    if (_speech.isAvailable) return;

    final ok = await _speech
        .initialize(
          onStatus: _onStatus,
          onError: _onError,
          debugLogging: kDebugMode,
          finalTimeout: const Duration(milliseconds: 4000),
        )
        .timeout(
          initTimeout,
          onTimeout: () =>
              throw TimeoutException('语音识别初始化超时', initTimeout),
        );

    if (ok != true) {
      throw VoiceInputUnavailableException(
        '无法启动语音识别（可能被拒绝麦克风权限或本机不支持）。'
        'Windows 请在「设置 → 时间和语言 → 语言和区域」安装中文，并在「语音」中启用在线语音识别；'
        '并确认麦克风权限已开启。',
      );
    }
    unawaited(_ensureLocaleCaches());
  }

  static String? _pickLocaleIdSync(String speechMode) {
    final list = _cachedLocales;
    if (list == null || list.isEmpty) return null;

    bool isZh(LocaleName l) {
      final id = l.localeId.toLowerCase();
      return id.startsWith('zh') ||
          id.contains('chinese') ||
          id.contains('_cn') ||
          id.contains('hans') ||
          id.contains('hant');
    }

    bool looksDialect(LocaleName l) {
      final id = l.localeId.toLowerCase();
      return id.contains('hk') ||
          id.contains('hant') ||
          id.contains('tw') ||
          id.contains('mo') ||
          id.contains('yue') ||
          id.contains('cant');
    }

    String? sysZhId() {
      final sys = _cachedSystemLocale;
      if (sys != null && isZh(sys)) return sys.localeId;
      return null;
    }

    switch (speechMode) {
      case '普通话优先':
        for (final l in list) {
          if (isZh(l) &&
              !looksDialect(l) &&
              (l.localeId.toLowerCase().contains('cn') ||
                  l.localeId.toLowerCase().contains('hans'))) {
            return l.localeId;
          }
        }
        for (final l in list) {
          if (isZh(l) && !looksDialect(l)) return l.localeId;
        }
        final s = sysZhId();
        if (s != null) return s;
        for (final l in list) {
          if (isZh(l)) return l.localeId;
        }
        return null;
      case '方言优先':
        for (final l in list) {
          if (looksDialect(l)) return l.localeId;
        }
        for (final l in list) {
          if (isZh(l)) return l.localeId;
        }
        return sysZhId();
      default:
        final s = sysZhId();
        if (s != null) return s;
        for (final l in list) {
          if (isZh(l)) return l.localeId;
        }
        return null;
    }
  }

  /// [engine]：`vivo`（默认，录完上传代理）或 `system`（系统听写）。
  static Future<String> listenOnce({
    required String speechMode,
    String engine = 'vivo',
  }) async {
    if (engine == 'vivo') {
      _sessionUsesVivo = true;
      try {
        return await VivoAsrInputService.listenOnce();
      } catch (e, st) {
        debugPrint('[VoiceInput] vivo ASR 失败，回退系统识别: $e\n$st');
        _sessionUsesVivo = false;
        return _listenOnceSystem(speechMode: speechMode);
      } finally {
        _sessionUsesVivo = false;
      }
    }
    return _listenOnceSystem(speechMode: speechMode);
  }

  static Future<String> _listenOnceSystem({required String speechMode}) async {
    _stopRequested = false;
    _endedByUserStopButton = false;
    _resetTranscript();
    _openListenSession = false;

    await _ensureInitialized();
    await _ensureLocaleCaches();

    if (_stopRequested) {
      _stopRequested = false;
      return '';
    }

    _sessionResult = Completer<String>();
    final completer = _sessionResult!;

    if (_stopRequested) {
      _stopRequested = false;
      _finishSession('');
      return await completer.future;
    }

    final localeId = _pickLocaleIdSync(speechMode);
    debugPrint('[VoiceInput] localeId=$localeId mode=$speechMode (sync pick)');

    if (_stopRequested) {
      _stopRequested = false;
      _finishSession('');
      return await completer.future;
    }

    try {
      await _speech.listen(
        onResult: _onResult,
        localeId: localeId,
        listenFor: listenForMax,
        pauseFor: null,
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } on ListenFailedException catch (e) {
      _finishSession('');
      throw VoiceInputListenException(
        e.message ?? '无法开始聆听',
      );
    }

    _openListenSession = true;
    try {
      final startDeadline = DateTime.now().add(listenStartTimeout);
      while (DateTime.now().isBefore(startDeadline) &&
          _speech.isNotListening &&
          !_stopRequested &&
          !completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      if (!completer.isCompleted &&
          _speech.isNotListening &&
          _bestSessionText().isEmpty) {
        debugPrint(
          '[VoiceInput] 未在 ${listenStartTimeout.inSeconds}s 内进入聆听或无识别文本，结束会话',
        );
        _finishSession('');
      }

      return await completer.future.timeout(
        sessionHardTimeout,
        onTimeout: () async {
          await _forceStopSession();
          return _bestSessionText();
        },
      );
    } finally {
      _openListenSession = false;
    }
  }

  static Future<void> stopFromUser() async {
    if (_sessionUsesVivo) {
      await VivoAsrInputService.stopFromUser();
      return;
    }
    _endedByUserStopButton = true;
    _stopRequested = true;
    try {
      await _speech.stop().timeout(stopFromUserTimeout, onTimeout: () {});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_sessionResult != null && !_sessionResult!.isCompleted) {
      _finishSession();
    }
  }

  static Future<void> _forceStopSession() async {
    try {
      if (_speech.isListening) {
        await _speech
            .stop()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      }
    } catch (_) {}
    try {
      if (_speech.isListening) {
        await _speech
            .cancel()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      }
    } catch (_) {}
    if (_sessionResult != null && !_sessionResult!.isCompleted) {
      _sessionResult!.complete(_bestSessionText());
    }
    _sessionResult = null;
  }

  static Future<void> cancelForDispose() async {
    _stopRequested = true;
    await Future.wait<void>([
      VivoAsrInputService.cancelForDispose(),
      _forceStopSession(),
    ]);
  }
}
