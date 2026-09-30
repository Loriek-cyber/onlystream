//import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  //dotenv.env['API_URL'] ??
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: "http://100.106.152.50:5555",
  );
}
