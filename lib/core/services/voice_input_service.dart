import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 封装系统语音识别（手机 / Windows 桌面 / Web 等由插件决定），带初始化与多段超时，避免阻塞。
class VoiceInputService {
  VoiceInputService._();

  static final SpeechToText _speech = SpeechToText();

  static Completer<String>? _sessionResult;
  static bool _stopRequested = false;
  static bool _endedByUserStopButton = false;

  /// 一次点击「开始」到「结束」只维护 **一整段** 文字（partial/final 均并入，避免短时分片）。
  static String _sessionLine = '';

  /// 已成功 [listen] 且尚未完成 [listenOnce]：此期间忽略引擎中间的 [done]，防止断续、多次收尾。
  static bool _openListenSession = false;

  static List<LocaleName>? _cachedLocales;
  static LocaleName? _cachedSystemLocale;

  static const Duration initTimeout = Duration(seconds: 12);

  /// 单次聆听最长上限（到点由插件停止）；用户未点击结束前不因静音自动停止（pauseFor 为 null）。
  static const Duration listenForMax = Duration(minutes: 5);

  /// 整段会话硬超时（略长于 [listenForMax]，便于收尾拿 final 文本并入对话）。
  static const Duration sessionHardTimeout = Duration(seconds: 310);

  static const Duration stopFromUserTimeout = Duration(seconds: 5);

  /// listen() 返回后等待进入真正「正在听」的最长时间；超时则立即结束，避免卡住 UI。
  static const Duration listenStartTimeout = Duration(seconds: 5);

  static bool get isEngineAvailable => _speech.isAvailable;

  /// 进入应用后后台调用：提前 [initialize] + 拉取语言列表，使首次点击「开始说话」后尽快 [listen]。
  static Future<void> prepareEngine() async {
    try {
      await _ensureInitialized();
      await _ensureLocaleCaches();
    } catch (_) {
      // 预热失败不阻断，用户点击时会再试
    }
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
    final v = _endedByUserStopButton;
    _endedByUserStopButton = false;
    return v;
  }

  static void _resetTranscript() {
    _sessionLine = '';
  }

  /// 将引擎给出的字符串并入「一整段」：同句变长用前缀规则；新起一句则直接拼接（无空格，避免中间断成多条消息）。
  /// 识别引擎在 partial/final、分句之间有时不保证「新串是旧串前缀」，直接拼接会乱序或丢字；
  /// 先做后缀/前缀重叠合并，再在 final 或整段刷新时用标点/空格连接。
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
    // 用户已点结束，或引擎已停止（如 listenFor 到点）：允许收尾
    if (_endedByUserStopButton || _speech.isNotListening) {
      _finishSession();
      return;
    }
    // 仍在聆听中却收到 done：多为中间分片，不结束本轮，保证「一点击一整段」直到用户点结束
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

  /// 使用已缓存的 [locales] / [systemLocale]，避免每次点击再等异步列表。
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

  /// 开始一次聆听，直到：[stopFromUser]、[listenForMax]（最长 5 分钟）、系统错误或永久错误。
  /// 识别时段 = 点击开始到点击结束；点击结束时将当前累积的 **全部** 文本合并为一条返回并写入对话。
  static Future<String> listenOnce({required String speechMode}) async {
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
        debugPrint('[VoiceInput] 未在 ${listenStartTimeout.inSeconds}s 内进入聆听或无识别文本，结束会话');
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

  /// 用户再次点击语音条时调用：尽快结束识别并拿到当前文本。
  static Future<void> stopFromUser() async {
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
    await _forceStopSession();
  }
}

class VoiceInputUnavailableException implements Exception {
  VoiceInputUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VoiceInputListenException implements Exception {
  VoiceInputListenException(this.message);
  final String message;

  @override
  String toString() => message;
}
