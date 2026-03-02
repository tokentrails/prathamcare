class AppConstants {
  AppConstants._();

  static const String appName = 'PrathamCare';
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://kinqjy55xg.execute-api.ap-south-1.amazonaws.com/dev');
}
