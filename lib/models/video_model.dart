import 'package:onlystream/utils/constants.dart';

class AudioTrack {
  final String language; // "it", "en"
  final String code; // "it", "en" (per le query)

  AudioTrack({required this.language, required this.code});
}

class Episode {
  final int season;
  final int number;
  final String? title;

  Episode({required this.season, required this.number, this.title});
}

class Video {
  final int id;
  final String title;
  final String type; // "movie" o "series"
  final List<AudioTrack> audioTracks;
  final Episode? currentEpisode;
  final Episode? nextEpisode;
  final bool hasNext;

  Video({
    required this.id,
    required this.title,
    required this.type,
    required this.audioTracks,
    this.currentEpisode,
    this.nextEpisode,
    this.hasNext = false,
  });

  // Factory constructor per parsare la risposta API
  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      id: json['tmdb_id'] as int,
      title: json['title'] as String? ?? 'Unknown',
      type: json['media_type'] as String,
      audioTracks: [],
      currentEpisode: json['media_type'] == 'tv'
          ? Episode(
              season: json['current_season'] as int,
              number: json['current_episode'] as int,
              title: json['episode_title'] as String?,
            )
          : null,
      nextEpisode: json['media_type'] == 'tv' && json['has_next'] == true
          ? Episode(
              season: json['next_season'] as int,
              number: json['next_episode'] as int,
              title: json['next_episode_title'] as String?,
            )
          : null,
      hasNext: json['has_next'] as bool? ?? false,
    );
  }

  /// Costruisci l'URL dello stream M3U8/HLS.
  /// Il backend dovrebbe restituire un playlist .m3u8
  String getStreamUrl({String language = 'it'}) {
    if (type == "movie") {
      return "${AppConstants.baseUrl}/movie/$id/?lang=$language";
    } else {
      final season = currentEpisode?.season ?? 0;
      final episode = currentEpisode?.number ?? 0;
      return "${AppConstants.baseUrl}/tv/$id/$season/$episode/?lang=$language";
    }
  }

  // Metodo helper: ottieni l'URL dell'episodio successivo
  String? getNextStreamUrl({String language = 'it'}) {
    if (!hasNext || nextEpisode == null) return null;

    final season = nextEpisode!.season;
    final episode = nextEpisode!.number;
    return "${AppConstants.baseUrl}/tv/$id/$season/$episode/?lang=$language";
  }
}
