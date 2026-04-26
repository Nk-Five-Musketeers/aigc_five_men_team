import 'package:dio/dio.dart';

import '../config/constants.dart';

class ApiClient {
  ApiClient()
      : dio = Dio(
          BaseOptions(
            baseUrl: AppConstants.apiBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${AppConstants.apiKey}',
            },
          ),
        );

  final Dio dio;
}
