import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../config/constants.dart';

/// 上传录音至本地代理，由 [server/speech_recognition.py] 调用 vivo ASR。
class AsrRepository {
  AsrRepository({Dio? dio}) : _dio = dio ?? _createBinaryDio();

  /// 勿复用 [ApiClient] 的 Dio：其默认 `application/json` 会导致代理拒收音频并中断连接。
  final Dio _dio;

  static Dio _createBinaryDio() {
    return Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 90),
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  }

  Future<String> transcribeWavFile(
    File file, {
    Duration recordingDuration = Duration.zero,
  }) async {
    if (!await file.exists()) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/asr/transcribe'),
        message: '录音文件不存在',
      );
    }
    final mode =
        recordingDuration.inSeconds > 0 && recordingDuration.inSeconds <= 55
            ? 'short'
            : 'long';

    final bytes = await file.readAsBytes();
    if (bytes.length < 44) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/asr/transcribe'),
        message: '录音过短，请重新说话',
      );
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/asr/transcribe',
      queryParameters: <String, dynamic>{'mode': mode},
      data: Uint8List.fromList(bytes),
      options: Options(
        headers: const {
          Headers.contentTypeHeader: 'audio/wav',
        },
        responseType: ResponseType.json,
      ),
    );

    final status = response.statusCode ?? 0;
    final Map<String, dynamic>? data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : null;
    if (status < 200 || status >= 300) {
      final err = data?['error']?.toString();
      final detail = data?['detail']?.toString();
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: err ?? detail ?? 'vivo 语音识别失败 (HTTP $status)',
      );
    }

    final ok = data?['ok'] == true;
    final text = (data?['text'] as String?)?.trim() ?? '';
    if (!ok || text.isEmpty) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: data?['error']?.toString() ?? 'vivo 语音识别结果为空',
      );
    }
    return text;
  }
}
