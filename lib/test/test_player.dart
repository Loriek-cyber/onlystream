import 'package:onlystream/models/video_model.dart';

/// Dati di test per lo sviluppo
class TestData {
  // Serie TV: Breaking Bad
  static final Video breakingBadSeries = Video(
    id: 1396,
    title: 'Breaking Bad',
    type: 'series',
    audioTracks: [
      AudioTrack(language: 'Italiano', code: 'it'),
      AudioTrack(language: 'English', code: 'en'),
    ],
    currentEpisode: Episode(season: 1, number: 1, title: 'Pilot'),
    nextEpisode: Episode(season: 1, number: 2, title: 'Cat\'s in the Bag...'),
    hasNext: true,
  );

  // Film: Oppenheimer
  static final Video oppenheimer = Video(
    id: 872585,
    title: 'Oppenheimer',
    type: 'movie',
    audioTracks: [
      AudioTrack(language: 'Italiano', code: 'it'),
      AudioTrack(language: 'English', code: 'en'),
    ],
  );

  // Serie TV: Stranger Things
  static final Video strangerThings = Video(
    id: 66732,
    title: 'Stranger Things',
    type: 'series',
    audioTracks: [
      AudioTrack(language: 'Italiano', code: 'it'),
      AudioTrack(language: 'English', code: 'en'),
      AudioTrack(language: 'Español', code: 'es'),
    ],
    currentEpisode: Episode(season: 1, number: 1, title: 'The Vanishing of Will Byers'),
    nextEpisode: Episode(season: 1, number: 2, title: 'The Weirdo on Maple Street'),
    hasNext: true,
  );
}
