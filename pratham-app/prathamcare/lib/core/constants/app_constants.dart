class AppConstants {
  AppConstants._();

  static const String appName = 'PrathamCare';
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000');
}
