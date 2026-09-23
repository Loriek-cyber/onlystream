import 'package:onlystream/utils/constants.dart';

// [Audio_Track_Model]
class AudioTrack {
  final String language; // Language name ("Italiano", "English")
  final String code; // Language ISO code ("it", "en")

  AudioTrack({required this.language, required this.code});
}

// [Episode_Model]
class Episode {
  final int season;
  final int number;
  final String? title;

  Episode({required this.season, required this.number, this.title});
}

// [Video_Model]
class Video {
  final int id;
  final String title;
  final String type; // "movie" or "series"
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

  // Factory constructor for parsing API response
  factory Video.fromJson(Map<String, dynamic> json) {
    final mediaType = json['media_type'] as String? ?? 'movie';
    final isTv = mediaType == 'tv' || mediaType == 'series';
    final hasNext = json['has_next'] as bool? ?? false;

    // Current episode fields (supporting both new and old API key schemas)
    final season =
        json['season'] as int? ?? json['current_season'] as int? ?? 1;
    final episodeNum =
        json['episode'] as int? ?? json['current_episode'] as int? ?? 1;
    final episodeTitle =
        json['episode_name'] as String? ?? json['episode_title'] as String?;

    // Next episode fields
    final nextSeason = json['next_season'] as int?;
    final nextEpNum = json['next_episode'] as int?;
    final nextEpTitle = json['next_episode_title'] as String?;

    return Video(
      id: json['tmdb_id'] as int? ?? 0,
      title:
          json['series_name'] as String? ??
          json['title'] as String? ??
          'Unknown',
      type: isTv ? 'series' : mediaType,
      audioTracks: [],
      currentEpisode: isTv
          ? Episode(season: season, number: episodeNum, title: episodeTitle)
          : null,
      nextEpisode: isTv && hasNext && nextSeason != null && nextEpNum != null
          ? Episode(season: nextSeason, number: nextEpNum, title: nextEpTitle)
          : null,
      hasNext: hasNext,
    );
  }

  /// Construct the M3U8/HLS stream URL.
  /// The backend returns an .m3u8 playlist.
  String getStreamUrl({String language = 'it'}) {
    if (type == "movie") {
      return "http://${AppConstants.baseUrl}/movie/$id/?lang=$language";
    } else {
      final season = currentEpisode?.season ?? 0;
      final episode = currentEpisode?.number ?? 0;
      return "http://${AppConstants.baseUrl}/tv/$id/$season/$episode/?lang=$language";
    }
  }

  /// Helper method: get next episode stream URL.
  String? getNextStreamUrl({String language = 'it'}) {
    if (!hasNext || nextEpisode == null) return null;

    final season = nextEpisode!.season;
    final episode = nextEpisode!.number;
    return "http://${AppConstants.baseUrl}/tv/$id/$season/$episode/?lang=$language";
  }
}
