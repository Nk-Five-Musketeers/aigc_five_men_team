import 'package:dio/dio.dart';

import '../config/constants.dart';

class ApiClient {
  ApiClient()
      : dio = Dio(
          BaseOptions(
            baseUrl: AppConstants.apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            // 本地代理转发上游大模型时可能较慢，需留足读超时
            receiveTimeout: const Duration(seconds: 120),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
            },
          ),
        );

  final Dio dio;
}
