import 'package:onlystream/services/api/api_client.dart';

class MovieApi {
  /// Genera l'URL di streaming HLS (.m3u8) diretto per la riproduzione di un film.
  /// Endpoint: GET /movie/{tmdb_id}/?lang={lang}
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB del film (es. '550').
  ///   - `lang` (String, default 'it'): Lingua audio preferita ('it' o 'en').
  /// Ritorna:
  ///   - `String`: Stringa dell'URL completo per il player video HLS.
  static String getStreamUrl(String tmdbId, {String lang = 'it'}) {
    return ApiClient.buildUrl('/movie/$tmdbId/', queryParameters: {'lang': lang});
  }

  /// Recupera i dettagli tecnici del flusso video (playlist_url, tracce audio, sottotitoli e varianti di qualità).
  /// Endpoint: GET /movie/{tmdb_id}/?format=json&lang={lang}
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB del film.
  ///   - `lang` (String, default 'it'): Lingua preferita delle tracce.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto JSON StreamInfo con audio, sottotitoli e risoluzioni, oppure null in caso di errore.
  static Future<Map<String, dynamic>?> getStreamInfo(
    String tmdbId, {
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/movie/$tmdbId/',
      queryParameters: {'format': 'json', 'lang': lang},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Recupera le informazioni correnti del film verificando che si tratti di un titolo singolo.
  /// Endpoint: GET /movie/{tmdb_id}/?currentInfo=true&lang={lang}
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB del film.
  ///   - `lang` (String, default 'it'): Lingua dei metadati.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto NextEpisodeResponse con has_next: false e dettagli film.
  static Future<Map<String, dynamic>?> getCurrentInfo(
    String tmdbId, {
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/movie/$tmdbId/',
      queryParameters: {'currentInfo': 'true', 'lang': lang},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }
}
