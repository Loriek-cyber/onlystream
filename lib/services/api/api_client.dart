import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:onlystream/utils/constants.dart';

class ApiClient {
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Effettua una richiesta HTTP GET verso il server EasyStream API.
  /// Riceve:
  ///   - `endpoint` (String): Il path relativo dell'endpoint (es. '/search').
  ///   - `queryParameters` (`Map<String, dynamic>?`): Parametri di query opzionali (es. {'q': 'batman', 'lang': 'it'}).
  ///   - `timeout` (Duration): Timeout massimo della richiesta (default: 10 secondi).
  /// Ritorna:
  ///   - `Future<dynamic>`: Risultato JSON decodificato (Map o List), oppure null se la richiesta fallisce.
  static Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    Duration timeout = defaultTimeout,
  }) async {
    try {
      final sanitizedParams = queryParameters?.map(
        (key, value) => MapEntry(key, value.toString()),
      );
      final uri = Uri.parse('${AppConstants.baseUrl}$endpoint').replace(
        queryParameters: sanitizedParams,
      );
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(response.body);
      }
      debugPrint('[ApiClient] GET $uri failed with status: ${response.statusCode}');
    } catch (e) {
      debugPrint('[ApiClient] GET $endpoint error: $e');
    }
    return null;
  }

  /// Effettua una richiesta HTTP POST con payload JSON verso il server EasyStream API.
  /// Riceve:
  ///   - `endpoint` (String): Il path relativo dell'endpoint (es. '/favorites').
  ///   - `body` (`Map<String, dynamic>`): Mappa dei parametri da serializzare in formato JSON.
  ///   - `timeout` (Duration): Timeout massimo della richiesta (default: 10 secondi).
  /// Ritorna:
  ///   - `Future<dynamic>`: Risultato JSON decodificato, oppure null se la richiesta fallisce.
  static Future<dynamic> post(
    String endpoint, {
    required Map<String, dynamic> body,
    Duration timeout = defaultTimeout,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(response.body);
      }
      debugPrint('[ApiClient] POST $uri failed with status: ${response.statusCode}');
    } catch (e) {
      debugPrint('[ApiClient] POST $endpoint error: $e');
    }
    return null;
  }

  /// Effettua una richiesta HTTP DELETE verso il server EasyStream API.
  /// Riceve:
  ///   - `endpoint` (String): Il path relativo dell'endpoint (es. '/favorites/movie/550').
  ///   - `timeout` (Duration): Timeout massimo della richiesta (default: 10 secondi).
  /// Ritorna:
  ///   - `Future<dynamic>`: Risultato JSON decodificato, oppure null se la richiesta fallisce.
  static Future<dynamic> delete(
    String endpoint, {
    Duration timeout = defaultTimeout,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
      final response = await http.delete(uri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(response.body);
      }
      debugPrint('[ApiClient] DELETE $uri failed with status: ${response.statusCode}');
    } catch (e) {
      debugPrint('[ApiClient] DELETE $endpoint error: $e');
    }
    return null;
  }

  /// Costruisce l'URL completo verso il server EasyStream API con eventuali query parameters.
  /// Riceve:
  ///   - `path` (String): Percorso relativo dell'endpoint (es. '/movie/550/').
  ///   - `queryParameters` (`Map<String, dynamic>?`): Parametri di query facoltativi (es. {'lang': 'it'}).
  /// Ritorna:
  ///   - `String`: Stringa dell'URL completo pronto per essere fornito a player video o browser.
  static String buildUrl(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    final sanitizedParams = queryParameters?.map(
      (key, value) => MapEntry(key, value.toString()),
    );
    final uri = Uri.parse('${AppConstants.baseUrl}$path').replace(
      queryParameters: sanitizedParams,
    );
    return uri.toString();
  }
}
