/// Unified TMDB media kind used across EasyStream API v1.0.0.
enum MediaKind {
  movie('movie'),
  tv('tv');

  const MediaKind(this.wireValue);

  final String wireValue;

  static MediaKind fromWire(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'tv':
      case 'series':
        return MediaKind.tv;
      case 'movie':
      default:
        return MediaKind.movie;
    }
  }
}

/// Information about the upcoming episode for series or anime playback.
class NextEpisodeInfo {
  final int season;
  final int episode;
  final String? name;
  final String? still;
  final String? airDate;

  const NextEpisodeInfo({
    required this.season,
    required this.episode,
    this.name,
    this.still,
    this.airDate,
  });

  factory NextEpisodeInfo.fromJson(Map<String, dynamic> json) {
    return NextEpisodeInfo(
      season: (json['season'] as num?)?.toInt() ?? 1,
      episode: (json['episode'] as num?)?.toInt() ?? 1,
      name: json['name'] as String?,
      still: json['still'] as String?,
      airDate: json['air_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'season': season,
        'episode': episode,
        if (name != null) 'name': name,
        if (still != null) 'still': still,
        if (airDate != null) 'air_date': airDate,
      };

  String get shortCode => 'S$season · E$episode';
}

String? parseYearField(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}
