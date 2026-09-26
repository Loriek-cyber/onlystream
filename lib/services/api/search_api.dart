import 'package:onlystream/models/video/movie_model.dart';
import 'package:onlystream/models/video/tv_show_model.dart';
import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/services/api/api_client.dart';

class SearchApi {
  /// Cerca film e serie TV sul database TMDB tramite query testuale.
  /// Endpoint: GET /search
  /// Riceve:
  ///   - `query` (String): Testo o titolo da ricercare (es. 'Breaking Bad').
  ///   - `type` (String, default 'all'): Filtro tipologia ('all', 'movie', 'tv').
  ///   - `lang` (String, default 'it'): Lingua dei metadati ('it' o 'en').
  /// Ritorna:
  ///   - `Future<List<VideoModel>>`: Lista di risultati polimorfici (MovieModel o TvShowModel).
  static Future<List<VideoModel>> search(
    String query, {
    String type = 'all',
    String lang = 'it',
  }) async {
    final data = await ApiClient.get(
      '/search',
      queryParameters: {'q': query, 'type': type, 'lang': lang},
    );
    final List<VideoModel> videos = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final mediaType = item['media_type'] as String? ?? 'movie';
          final title = item['title'] as String? ?? item['name'] as String? ?? 'Unknown';
          final overview = item['overview'] as String? ?? '';
          final tmdbId = item['id']?.toString() ?? '0';
          final imageUrl = item['poster_url'] as String? ?? item['backdrop_url'] as String? ?? '';

          if (mediaType == 'tv' || mediaType == 'series') {
            videos.add(
              TvShowModel(
                name: title,
                description: overview,
                tmdb_id: tmdbId,
                url_image: imageUrl,
                sesson: [],
              ),
            );
          } else {
            videos.add(
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
    return videos;
  }
}
