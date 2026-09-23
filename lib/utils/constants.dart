//import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  //dotenv.env['API_URL'] ??
  static String baseUrl = String.fromEnvironment(
    "API_URL",
    defaultValue: "http://localhost:5555",
  );
}
