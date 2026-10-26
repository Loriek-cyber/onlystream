import 'package:onlystream/services/server_config_service.dart';

class AppConstants {
  static const String _envUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:5555',
  );

  /// Dynamic base URL pointing to the configured EasyStream API server.
  static String get baseUrl => ServerConfigService.instance.baseUrl;

  static String get defaultUrl =>
      _envUrl.isNotEmpty ? _envUrl : 'http://localhost:5555';
}
