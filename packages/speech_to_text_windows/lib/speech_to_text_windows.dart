import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Windows 原生 `textRecognition` 仅发送 `recognizedWords` + `finalResult`，
/// 而 `speech_to_text` 的 [SpeechRecognitionResult.fromJson] 需要 `alternates`
/// 与 `confidence`，否则抛出 type cast 异常、识别结果无法进入 Dart。
String _patchWindowsRecognitionJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return raw;
    final map = Map<String, dynamic>.from(
      decoded.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (map['alternates'] is List) return raw;

    final words = map['recognizedWords']?.toString() ?? '';
    final fr = map['finalResult'] == true;
    final fixed = <String, dynamic>{
      'alternates': [
        <String, dynamic>{
          'recognizedWords': words,
          'recognizedPhrases': null,
          'confidence': -1,
        },
      ],
      'finalResult': fr,
    };
    return jsonEncode(fixed);
  } catch (_) {
    return raw;
  }
}

/// Windows implementation of the speech_to_text plugin (SAPI).
class SpeechToTextWindows extends SpeechToTextPlatform {
  static const MethodChannel _channel = MethodChannel('speech_to_text_windows');

  static void registerWith() {
    SpeechToTextPlatform.instance = SpeechToTextWindows();
  }

  SpeechToTextWindows();

  @override
  Future<bool> hasPermission() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking microphone permission: $e');
      }
      return false;
    }
  }

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async {
    _channel.setMethodCallHandler(_handleMethodCall);

    final Map<String, dynamic> params = {
      'debugLogging': debugLogging,
    };

    if (options != null) {
      for (final option in options) {
        if (option.platform == 'windows') {
          params[option.name] = option.value;
        }
      }
    }

    try {
      final bool? result =
          await _channel.invokeMethod<bool>('initialize', params);
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing Windows speech recognition: $e');
      }
      return false;
    }
  }

  @override
  Future<bool> listen({
    String? localeId,
    @Deprecated('Use SpeechListenOptions.partialResults instead')
    partialResults = true,
    @Deprecated('Use SpeechListenOptions.onDevice instead')
    onDevice = false,
    @Deprecated('Use SpeechListenOptions.listenMode instead')
    int listenMode = 0,
    @Deprecated('Use SpeechListenOptions.sampleRate instead')
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    final Map<String, dynamic> params = {
      'localeId': localeId,
      'partialResults': options?.partialResults ?? partialResults,
      'onDevice': options?.onDevice ?? onDevice,
      'listenMode': options?.listenMode.index ?? listenMode,
      'sampleRate': options?.sampleRate ?? sampleRate,
      'autoPunctuation': options?.autoPunctuation ?? false,
      'enableHapticFeedback': options?.enableHapticFeedback ?? false,
      'cancelOnError': options?.cancelOnError ?? false,
    };

    try {
      final bool? result = await _channel.invokeMethod<bool>('listen', params);
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('Error starting speech recognition: $e');
      }
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping speech recognition: $e');
      }
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (e) {
      if (kDebugMode) {
        print('Error canceling speech recognition: $e');
      }
    }
  }

  @override
  Future<List<dynamic>> locales() async {
    try {
      final List<dynamic>? result =
          await _channel.invokeMethod<List<dynamic>>('locales');
      return result ?? [];
    } catch (e) {
      if (kDebugMode) {
        print('Error getting supported locales: $e');
      }
      return [];
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'textRecognition':
          if (call.arguments is String && onTextRecognition != null) {
            final patched =
                _patchWindowsRecognitionJson(call.arguments as String);
            onTextRecognition!(patched);
          }
          break;
        case 'notifyError':
          if (call.arguments is String && onError != null) {
            onError!(call.arguments);
          }
          break;
        case 'notifyStatus':
          if (call.arguments is String && onStatus != null) {
            onStatus!(call.arguments);
          }
          break;
        case 'soundLevelChange':
          if (call.arguments is double && onSoundLevel != null) {
            onSoundLevel!(call.arguments);
          }
          break;
        default:
          if (kDebugMode) {
            print('Unknown method call: ${call.method}');
          }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling method call ${call.method}: $e');
      }
    }
  }
}
