import 'package:onlystream/utils/constants.dart';

class AudioTrack {
  final String language; // "it", "en"
  final String code; // "it", "en" (per le query)

  AudioTrack({required this.language, required this.code});
}



class Video {
  final int id;
  final String title;
  final String type; // "movie" o "series"
  final List<AudioTrack> audioTracks;
  final Video? nextEpisode;

  Video({
    required this.id,
    required this.title,
    required this.type,
    required this.audioTracks,
    this.nextEpisode,
    
  });




  // Metodo helper: costruisci l'URL dello stream
  String getStreamUrl(String language) {
    if (type == "movie") {
      return "${AppConstants.baseUrl}/movie/$id/?lang=$language";
    } else {
      print(
        "${AppConstants.baseUrl}/tv/$id/${currentEpisode?.season}/${currentEpisode?.number}/?lang=$language",
      );
      return "${AppConstants.baseUrl}/tv/$id/${currentEpisode?.season}/${currentEpisode?.number}/?lang=$language";
    }
  }
}
