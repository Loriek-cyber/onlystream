import 'package:onlystream/services/api/api_client.dart';

class AnimeApi {
  /// Genera l'URL di streaming HLS diretto per un episodio di una serie anime (AnimeUnity).
  /// Endpoint: GET /anime/{anime_id}/{episode}/
  /// Riceve:
  ///   - `animeId` (String): ID numerico AnimeUnity della serie (es. '4290').
  ///   - `episode` (int): Numero dell'episodio (es. 1).
  /// Ritorna:
  ///   - `String`: Stringa dell'URL completo pronto per il player video.
  static String getStreamUrl(String animeId, int episode) {
    return ApiClient.buildUrl('/anime/$animeId/$episode/');
  }

  /// Recupera i dettagli tecnici dello streaming di un episodio anime in formato JSON (StreamInfo).
  /// Endpoint: GET /anime/{anime_id}/{episode}/?format=json
  /// Riceve:
  ///   - `animeId` (String): ID numerico AnimeUnity dell'anime.
  ///   - `episode` (int): Numero dell'episodio.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto JSON StreamInfo con playlist_url, m3u8_content e varianti.
  static Future<Map<String, dynamic>?> getStreamInfo(
    String animeId,
    int episode,
  ) async {
    final data = await ApiClient.get(
      '/anime/$animeId/$episode/',
      queryParameters: {'format': 'json'},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Recupera i metadati dell'episodio anime attualmente in riproduzione.
  /// Endpoint: GET /anime/{anime_id}/{episode}/?currentInfo=true
  /// Riceve:
  ///   - `animeId` (String): ID numerico AnimeUnity dell'anime.
  ///   - `episode` (int): Numero dell'episodio.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto AnimeNextEpisodeResponse con dettagli dell'episodio corrente.
  static Future<Map<String, dynamic>?> getCurrentInfo(
    String animeId,
    int episode,
  ) async {
    final data = await ApiClient.get(
      '/anime/$animeId/$episode/',
      queryParameters: {'currentInfo': 'true'},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Calcola e restituisce le informazioni sul prossimo episodio dell'anime disponibile su AnimeUnity.
  /// Endpoint: GET /anime/{anime_id}/{episode}/?nextepisode=true
  /// Riceve:
  ///   - `animeId` (String): ID numerico AnimeUnity dell'anime.
  ///   - `episode` (int): Numero dell'episodio attuale.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto AnimeNextEpisodeResponse con has_next e next_episode.
  static Future<Map<String, dynamic>?> getNextEpisode(
    String animeId,
    int episode,
  ) async {
    final data = await ApiClient.get(
      '/anime/$animeId/$episode/',
      queryParameters: {'nextepisode': 'true'},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Recupera l'elenco completo di tutti gli episodi disponibili per un anime.
  /// Endpoint: GET /anime/{anime_id}/episodes
  /// Riceve:
  ///   - `animeId` (String): ID numerico AnimeUnity dell'anime.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Oggetto AnimeEpisodesResponse con episodes_count e lista episodi con id, number, file_name.
  static Future<Map<String, dynamic>?> getEpisodes(String animeId) async {
    final data = await ApiClient.get('/anime/$animeId/episodes');
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Esegue una ricerca di anime per titolo tramite la LiveSearch di AnimeUnity.
  /// Endpoint: GET /anime/search?q={query}
  /// Riceve:
  ///   - `query` (String): Testo o titolo dell'anime da cercare (es. 'Solo Leveling').
  /// Ritorna:
  ///   - `Future<List<Map<String, dynamic>>>`: Lista di oggetti AnimeRecord con id, titoli (it/eng), immagine di copertina e trama.
  static Future<List<Map<String, dynamic>>> search(String query) async {
    final data = await ApiClient.get(
      '/anime/search',
      queryParameters: {'q': query},
    );
    final List<Map<String, dynamic>> results = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          results.add(item);
        }
      }
    }
    return results;
  }
}
