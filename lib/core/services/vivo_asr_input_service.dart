import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../config/constants.dart';
import '../../data/repositories/asr_repository.dart';
import 'voice_input_service.dart';

/// 一期 vivo ASR：录完再上传本地代理识别（与 [VoiceInputService] 点击开始/结束交互一致）。
class VivoAsrInputService {
  VivoAsrInputService._();

  static final AudioRecorder _recorder = AudioRecorder();
  static final AsrRepository _asrRepository = AsrRepository();

  static Completer<String>? _sessionResult;
  static bool _endedByUserStopButton = false;
  static String? _recordingPath;
  static DateTime? _recordStartedAt;
  static bool _isRecording = false;

  static const Duration sessionHardTimeout = Duration(seconds: 310);

  static bool consumeEndedByUserStop() {
    final v = _endedByUserStopButton;
    _endedByUserStopButton = false;
    return v;
  }

  static Future<void> prepareEngine() async {
    try {
      await _recorder.hasPermission();
      await _probeAsrProxy();
    } catch (_) {}
  }

  /// 确认本地代理已启动且含 `/api/asr/transcribe`（避免旧进程占 8000 导致连接被重置）。
  static Future<void> _probeAsrProxy() async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.apiBaseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final res = await dio.get<Map<String, dynamic>>('/health');
      final data = res.data;
      if (data?['vivo_asr'] != true) {
        debugPrint(
          '[VivoASR] /health 无 vivo_asr，请重启最新版 python server/local_chat_server.py',
        );
      }
    } catch (e) {
      debugPrint('[VivoASR] 无法连接本地代理 ${AppConstants.apiBaseUrl}: $e');
    }
  }

  static Future<String> listenOnce() async {
    _endedByUserStopButton = false;
    _sessionResult = Completer<String>();

    if (!await _recorder.hasPermission()) {
      throw VoiceInputUnavailableException(
        '需要麦克风权限才能使用语音输入。请在系统设置中允许麦克风访问。',
      );
    }

    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/vivo_asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    _recordStartedAt = DateTime.now();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _recordingPath!,
    );
    _isRecording = true;
    debugPrint('[VivoASR] recording $_recordingPath');

    try {
      return await _sessionResult!.future.timeout(
        sessionHardTimeout,
        onTimeout: () async {
          await stopFromUser();
          return '';
        },
      );
    } finally {
      _isRecording = false;
    }
  }

  static Future<void> stopFromUser() async {
    _endedByUserStopButton = true;
    if (!_isRecording && _sessionResult == null) return;

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      final wavPath = path ?? _recordingPath;
      final started = _recordStartedAt;
      _recordingPath = null;
      _recordStartedAt = null;

      if (wavPath == null || wavPath.isEmpty) {
        _finishSession('');
        return;
      }

      final file = File(wavPath);
      if (!await file.exists() || await file.length() < 44) {
        _finishSession('');
        return;
      }

      final duration = started != null
          ? DateTime.now().difference(started)
          : Duration.zero;

      debugPrint('[VivoASR] upload ${file.path} duration=${duration.inSeconds}s');
      final text = await _asrRepository.transcribeWavFile(
        file,
        recordingDuration: duration,
      );
      _finishSession(text);
    } catch (e, st) {
      debugPrint('[VivoASR] stop/upload failed: $e\n$st');
      if (_sessionResult != null && !_sessionResult!.isCompleted) {
        _sessionResult!.completeError(e);
      }
    }
  }

  static void _finishSession(String text) {
    final c = _sessionResult;
    if (c != null && !c.isCompleted) {
      c.complete(text.trim());
    }
    _sessionResult = null;
  }

  static Future<void> cancelForDispose() async {
    try {
      if (_isRecording) {
        await _recorder.stop();
      }
    } catch (_) {}
    try {
      await _recorder.cancel();
    } catch (_) {}
    _isRecording = false;
    _recordingPath = null;
    if (_sessionResult != null && !_sessionResult!.isCompleted) {
      _sessionResult!.complete('');
    }
    _sessionResult = null;
  }
}
