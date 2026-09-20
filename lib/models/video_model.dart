import 'package:onlystream/utils/constants.dart';

class AudioTrack {
  final String language; // "it", "en"
  final String code; // "it", "en" (per le query)

  AudioTrack({required this.language, required this.code});
}

class Episode {
  final int number;
  final int season;
  final String title;
  Episode({required this.number, required this.season, required this.title});
}

class Video {
  final int id;
  final String title;
  final String type; // "movie" o "series"
  final List<AudioTrack> audioTracks;
  final Episode? currentEpisode; // null se è un film
  final Episode? nextEpisode; // null se è film o ultimo episodio
  final int duration;

  Video({
    required this.id,
    required this.title,
    required this.type,
    required this.audioTracks,
    this.currentEpisode,
    this.nextEpisode,
    required this.duration,
  });

  // Metodo helper: costruisci l'URL dello stream
  String getStreamUrl(String language) {
    if (type == "movie") {
      return "${AppConstants.baseUrl}/movie/$id/?lang=$language";
    } else {
      return "${AppConstants.baseUrl}/tv/$id/${currentEpisode?.season}/${currentEpisode?.number}/?lang=$language";
    }
  }
}
