import 'package:onlystream/models/video_model.dart';

class TestData {
  static Video breakingBadSeries = Video(
    id: 550,
    title: "test",
    type: "movie",
    audioTracks: [
      AudioTrack(language: "Italiano", code: "it"),
      AudioTrack(language: "English", code: "en"),
    ],
    currentEpisode: Episode(number: 1, season: 1, title: "Pilot"),
    nextEpisode: Episode(number: 2, season: 1, title: "Cat's in the Bag..."),
    duration: 2700, // 45 minuti
  );
}
