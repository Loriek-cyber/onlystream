import 'package:onlystream/models/video/movie_model.dart';
import 'package:onlystream/models/video/tv_show_model.dart';
import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/services/api/api.dart';

class VideoService {
  /// Risolve l'URL di streaming HLS (.m3u8) appropriato per un film o una serie TV.
  /// Riceve:
  ///   - `video` (VideoModel): Istanza del contenuto multimediale (MovieModel o TvShowModel).
  ///   - `season` (int, default 1): Numero della stagione per le serie TV.
  ///   - `episode` (int, default 1): Numero dell'episodio per le serie TV.
  ///   - `language` (String, default 'it'): Codice lingua dello stream.
  /// Ritorna:
  ///   - `String`: URL completo dello stream HLS.
  static String getStreamUrl(
    VideoModel video, {
    int season = 1,
    int episode = 1,
    String language = 'it',
  }) {
    if (video is MovieModel || video.getType() == 'movie') {
      return MovieApi.getStreamUrl(video.tmdb_id, lang: language);
    } else {
      return TvApi.getStreamUrl(video.tmdb_id, season, episode, lang: language);
    }
  }

  /// Recupera i metadati del prossimo episodio per una serie TV.
  /// Riceve:
  ///   - `tmdbId` (String): ID TMDB della serie televisiva.
  ///   - `season` (int): Numero della stagione corrente.
  ///   - `episode` (int): Numero dell'episodio corrente.
  ///   - `language` (String, default 'it'): Lingua dei metadati.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Mappa con i dettagli dell'episodio successivo (has_next, next_season, next_episode, episode_name).
  static Future<Map<String, dynamic>?> fetchNextEpisode({
    required String tmdbId,
    required int season,
    required int episode,
    String language = 'it',
  }) {
    return TvApi.getNextEpisode(tmdbId, season, episode, lang: language);
  }

  /// Recupera le informazioni descrittive dell'episodio corrente di una serie TV.
  /// Riceve:
  ///   - `tmdbId` (String): ID TMDB della serie televisiva.
  ///   - `season` (int): Numero della stagione.
  ///   - `episode` (int): Numero dell'episodio.
  ///   - `language` (String, default 'it'): Lingua dei metadati.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Mappa con i metadati dell'episodio corrente.
  static Future<Map<String, dynamic>?> fetchCurrentEpisodeInfo({
    required String tmdbId,
    required int season,
    required int episode,
    String language = 'it',
  }) {
    return TvApi.getCurrentInfo(tmdbId, season, episode, lang: language);
  }

  /// Recupera l'elenco delle stagioni e degli episodi per una serie TV.
  /// Riceve:
  ///   - `tmdbId` (String): ID TMDB della serie televisiva.
  ///   - `language` (String, default 'it'): Lingua dei titoli delle stagioni.
  /// Ritorna:
  ///   - `Future<List<Sesson>>`: Lista di oggetti Sesson con episodi enumerati.
  static Future<List<Sesson>> fetchTvSeasons(
    String tmdbId, {
    String language = 'it',
  }) {
    return DiscoveryApi.getTvSeasons(tmdbId, lang: language);
  }
}
