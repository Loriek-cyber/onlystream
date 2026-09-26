import 'package:onlystream/models/video/movie_model.dart';
import 'package:onlystream/models/video/tv_show_model.dart';
import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/services/api/api_client.dart';

class DiscoveryApi {
  /// Recupera l'elenco delle nuove serie TV attualmente in onda (On The Air / Nuove Uscite).
  /// Endpoint: GET /tv/new
  /// Riceve:
  ///   - `lang` (String, default 'it'): Lingua dei metadati ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<TvShowModel>>`: Lista delle nuove serie TV istanziate come TvShowModel.
  static Future<List<TvShowModel>> getNewSeries({String lang = 'it'}) async {
    final data = await ApiClient.get('/tv/new', queryParameters: {'lang': lang});
    final List<TvShowModel> series = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          series.add(
            TvShowModel(
              name: item['title'] as String? ?? item['name'] as String? ?? 'Unknown',
              description: item['overview'] as String? ?? '',
              tmdb_id: item['id']?.toString() ?? '0',
              url_image: item['poster_url'] as String? ?? item['backdrop_url'] as String? ?? '',
              sesson: [],
            ),
          );
        }
      }
    }
    return series;
  }

  /// Recupera l'elenco delle serie TV più popolari del momento.
  /// Endpoint: GET /tv/popular
  /// Riceve:
  ///   - `lang` (String, default 'it'): Lingua dei metadati ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<TvShowModel>>`: Lista delle serie TV più popolari come TvShowModel.
  static Future<List<TvShowModel>> getPopularSeries({String lang = 'it'}) async {
    final data = await ApiClient.get('/tv/popular', queryParameters: {'lang': lang});
    final List<TvShowModel> series = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          series.add(
            TvShowModel(
              name: item['title'] as String? ?? item['name'] as String? ?? 'Unknown',
              description: item['overview'] as String? ?? '',
              tmdb_id: item['id']?.toString() ?? '0',
              url_image: item['poster_url'] as String? ?? item['backdrop_url'] as String? ?? '',
              sesson: [],
            ),
          );
        }
      }
    }
    return series;
  }

  /// Recupera l'elenco delle serie TV con le valutazioni più alte della critica e del pubblico.
  /// Endpoint: GET /tv/top-rated
  /// Riceve:
  ///   - `lang` (String, default 'it'): Lingua dei metadati ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<TvShowModel>>`: Lista delle serie TV top rated come TvShowModel.
  static Future<List<TvShowModel>> getTopRatedSeries({String lang = 'it'}) async {
    final data = await ApiClient.get('/tv/top-rated', queryParameters: {'lang': lang});
    final List<TvShowModel> series = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          series.add(
            TvShowModel(
              name: item['title'] as String? ?? item['name'] as String? ?? 'Unknown',
              description: item['overview'] as String? ?? '',
              tmdb_id: item['id']?.toString() ?? '0',
              url_image: item['poster_url'] as String? ?? item['backdrop_url'] as String? ?? '',
              sesson: [],
            ),
          );
        }
      }
    }
    return series;
  }

  /// Recupera l'elenco dei film più popolari del momento.
  /// Endpoint: GET /movie/popular
  /// Riceve:
  ///   - `lang` (String, default 'it'): Lingua dei metadati ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<MovieModel>>`: Lista dei film più popolari come MovieModel.
  static Future<List<MovieModel>> getPopularMovies({String lang = 'it'}) async {
    final data = await ApiClient.get('/movie/popular', queryParameters: {'lang': lang});
    final List<MovieModel> movies = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          movies.add(
            MovieModel(
              name: item['title'] as String? ?? 'Unknown',
              description: item['overview'] as String? ?? '',
              tmdb_id: item['id']?.toString() ?? '0',
              url_image: item['poster_url'] as String? ?? item['backdrop_url'] as String? ?? '',
            ),
          );
        }
      }
    }
    return movies;
  }

  /// Recupera l'elenco dei film attualmente proiettati al cinema o usciti di recente in streaming.
  /// Endpoint: GET /movie/now-playing
  /// Riceve:
  ///   - `lang` (String, default 'it'): Lingua dei metadati ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<MovieModel>>`: Lista dei film now playing come MovieModel.
  static Future<List<MovieModel>> getNowPlayingMovies({String lang = 'it'}) async {
    final data = await ApiClient.get('/movie/now-playing', queryParameters: {'lang': lang});
    final List<MovieModel> movies = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          movies.add(
            MovieModel(
              name: item['title'] as String? ?? 'Unknown',
              description: item['overview'] as String? ?? '',
              tmdb_id: item['id']?.toString() ?? '0',
              url_image: item['poster_url'] as String? ?? item['backdrop_url'] as String? ?? '',
            ),
          );
        }
      }
    }
    return movies;
  }

  /// Recupera i contenuti (film e serie TV) attualmente di tendenza.
  /// Endpoint: GET /trending
  /// Riceve:
  ///   - `window` (String, default 'day'): Finestra temporale di calcolo ('day' o 'week').
  ///   - `lang` (String, default 'it'): Lingua dei metadati ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<VideoModel>>`: Lista di contenuti eterogenei (MovieModel o TvShowModel) in tendenza.
  static Future<List<VideoModel>> getTrending({
    String window = 'day',
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/trending',
      queryParameters: {'window': window, 'lang': lang},
    );
    final List<VideoModel> results = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final mediaType = item['media_type'] as String? ?? 'movie';
          final title = item['title'] as String? ?? item['name'] as String? ?? 'Unknown';
          final overview = item['overview'] as String? ?? '';
          final tmdbId = item['id']?.toString() ?? '0';
          final imageUrl = item['poster_url'] as String? ?? item['backdrop_url'] as String? ?? '';

          if (mediaType == 'tv' || mediaType == 'series') {
            results.add(
              TvShowModel(
                name: title,
                description: overview,
                tmdb_id: tmdbId,
                url_image: imageUrl,
                sesson: [],
              ),
            );
          } else {
            results.add(
              MovieModel(
                name: title,
                description: overview,
                tmdb_id: tmdbId,
                url_image: imageUrl,
              ),
            );
          }
        }
      }
    }
    return results;
  }

  /// Recupera la struttura completa di stagioni ed episodi disponibili per una serie TV.
  /// Endpoint: GET /tv/{tmdb_id}/seasons
  /// Riceve:
  ///   - `tmdbId` (String): ID numerico TMDB della serie televisiva.
  ///   - `lang` (String, default 'it'): Lingua dei nomi delle stagioni ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<Sesson>>`: Lista di oggetti Sesson contenenti ciascuno gli episodi generati con numerazione corretta.
  static Future<List<Sesson>> getTvSeasons(
    String tmdbId, {
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/tv/$tmdbId/seasons',
      queryParameters: {'lang': lang},
    );
    final List<Sesson> seasons = [];
    if (data is Map<String, dynamic> && data['seasons'] is List) {
      final List<dynamic> seasonsJson = data['seasons'];
      for (final s in seasonsJson) {
        if (s is Map<String, dynamic>) {
          final seasonNumber = s['season_number'] as int? ?? 1;
          final episodeCount = s['episode_count'] as int? ?? 0;
          final episodes = List.generate(
            episodeCount,
            (index) => Episode(
              'Episodio ${index + 1}',
              '',
              index + 1,
              '',
            ),
          );
          seasons.add(Sesson(seasonNumber, episodes));
        }
      }
    }
    return seasons;
  }
}
