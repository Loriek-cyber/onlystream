import 'package:onlystream/services/api/api_client.dart';

class TvApi {
  /// Genera l'URL di streaming HLS (.m3u8) diretto per uno specifico episodio di una serie TV.
  /// Endpoint: GET /tv/{tmdb_id}/{season}/{episode}/?lang={lang}
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB della serie televisiva (es. '1396').
  ///   - `season` (int): Numero della stagione (es. 1).
  ///   - `episode` (int): Numero dell'episodio (es. 1).
  ///   - `lang` (String, default 'it'): Lingua audio preferita ('it' o 'en').
  /// Ritorna:
  ///   - `String`: Stringa dell'URL completo per la riproduzione video HLS.
  static String getStreamUrl(
    String tmdbId,
    int season,
    int episode, {
    String lang = 'it',
  }) {
    return ApiClient.buildUrl(
      '/tv/$tmdbId/$season/$episode/',
      queryParameters: {'lang': lang},
    );
  }

  /// Recupera i metadati tecnici dello stream per l'episodio (tracce audio multilingua, sottotitoli e varianti bitrate).
  /// Endpoint: GET /tv/{tmdb_id}/{season}/{episode}/?format=json&lang={lang}
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB della serie televisiva.
  ///   - `season` (int): Numero della stagione.
  ///   - `episode` (int): Numero dell'episodio.
  ///   - `lang` (String, default 'it'): Lingua preferita.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto JSON StreamInfo con tracce audio e playlist m3u8.
  static Future<Map<String, dynamic>?> getStreamInfo(
    String tmdbId,
    int season,
    int episode, {
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/tv/$tmdbId/$season/$episode/',
      queryParameters: {'format': 'json', 'lang': lang},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Recupera le informazioni dell'episodio corrente (titolo ufficiale dell'episodio, nome della serie, disponibilità successivo).
  /// Endpoint: GET /tv/{tmdb_id}/{season}/{episode}/?currentInfo=true&lang={lang}
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB della serie televisiva.
  ///   - `season` (int): Numero della stagione.
  ///   - `episode` (int): Numero dell'episodio.
  ///   - `lang` (String, default 'it'): Lingua dei metadati.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto NextEpisodeResponse con i dati dell'episodio attuale.
  static Future<Map<String, dynamic>?> getCurrentInfo(
    String tmdbId,
    int season,
    int episode, {
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/tv/$tmdbId/$season/$episode/',
      queryParameters: {'currentInfo': 'true', 'lang': lang},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Calcola e restituisce i metadati del prossimo episodio (gestendo automaticamente il passaggio di stagione o fine serie).
  /// Endpoint: GET /tv/{tmdb_id}/{season}/{episode}/?nextepisode=true&lang={lang}
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB della serie televisiva.
  ///   - `season` (int): Numero della stagione corrente.
  ///   - `episode` (int): Numero dell'episodio corrente.
  ///   - `lang` (String, default 'it'): Lingua dei metadati.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto NextEpisodeResponse con has_next, next_season, next_episode e episode_name.
  static Future<Map<String, dynamic>?> getNextEpisode(
    String tmdbId,
    int season,
    int episode, {
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/tv/$tmdbId/$season/$episode/',
      queryParameters: {'nextepisode': 'true', 'lang': lang},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }
}
