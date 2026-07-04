import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../config/constants.dart';

abstract class TtsSynthesizer {
  Uri streamUri({
    required String text,
    String voice = 'wanqing',
    int speed = 50,
    int volume = 50,
  });

  Future<Uint8List> synthesize({
    required String text,
    String voice = 'wanqing',
    int speed = 50,
    int volume = 50,
  });
}

class TtsSynthesisException implements Exception {
  TtsSynthesisException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TtsRepository implements TtsSynthesizer {
  TtsRepository({Dio? dio}) : _dio = dio ?? _createBinaryDio();

  final Dio _dio;

  @override
  Uri streamUri({
    required String text,
    String voice = 'wanqing',
    int speed = 50,
    int volume = 50,
  }) {
    return Uri.parse('${AppConstants.apiBaseUrl}/api/tts/stream').replace(
      queryParameters: <String, String>{
        'text': text,
        'voice': voice,
        'speed': speed.toString(),
        'volume': volume.toString(),
      },
    );
  }

  static Dio _createBinaryDio() {
    return Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 30),
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  }

  @override
  Future<Uint8List> synthesize({
    required String text,
    String voice = 'wanqing',
    int speed = 50,
    int volume = 50,
  }) async {
    final response = await _dio.post<List<int>>(
      '/api/tts/synthesize',
      data: <String, dynamic>{
        'text': text,
        'voice': voice,
        'speed': speed,
        'volume': volume,
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {
          Headers.contentTypeHeader: 'application/json; charset=utf-8',
        },
      ),
    );

    final status = response.statusCode ?? 0;
    final bytes = response.data;
    if (status < 200 || status >= 300) {
      throw TtsSynthesisException(_decodeError(bytes, status));
    }
    if (bytes == null || bytes.isEmpty) {
      throw TtsSynthesisException('语音合成结果为空，请稍后重试。');
    }
    return Uint8List.fromList(bytes);
  }

  String _decodeError(List<int>? bytes, int status) {
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final payload = jsonDecode(utf8.decode(bytes));
        if (payload is Map) {
          final detail = payload['detail']?.toString();
          final error = payload['error']?.toString();
          if (detail != null && detail.isNotEmpty) return detail;
          if (error != null && error.isNotEmpty) return error;
        }
      } catch (_) {}
    }
    return '语音朗读暂时不可用 (HTTP $status)。';
  }
}
