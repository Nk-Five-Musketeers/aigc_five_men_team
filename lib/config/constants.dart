class AppConstants {
  AppConstants._();

  static const String appName = '暖忆陪伴';
  static const String modelId = 'Volc-DeepSeek-V3.2';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
