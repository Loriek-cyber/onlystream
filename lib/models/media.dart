import 'package:onlystream/models/library.dart';

export 'package:onlystream/models/common.dart';

class MediaSummary {
  final int id;
  final MediaKind kind;
  final bool isAnime;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? year;
  final double? rating;
  final String? poster;
  final String? backdrop;

  const MediaSummary({
    required this.id,
    required this.kind,
    this.isAnime = false,
    required this.title,
    this.originalTitle,
    this.overview,
    this.year,
    this.rating,
    this.poster,
    this.backdrop,
  });

  String get kindLabel {
    if (isAnime) return 'Anime';
    return kind == MediaKind.tv ? 'Serie TV' : 'Film';
  }

  factory MediaSummary.fromLibrary(LibraryItemView item) {
    return MediaSummary(
      id: item.id,
      kind: item.kind,
      isAnime: item.isAnime,
      title: item.title,
      year: item.year,
      poster: item.poster,
      backdrop: item.backdrop,
    );
  }

  factory MediaSummary.fromJson(Map<String, dynamic> json) {
    return MediaSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: MediaKind.fromWire(json['kind'] as String?),
      isAnime: json['is_anime'] as bool? ?? false,
      title: json['title'] as String? ?? 'Titolo sconosciuto',
      originalTitle: json['original_title'] as String?,
      overview: json['overview'] as String?,
      year: parseYearField(json['year']),
      rating: (json['rating'] as num?)?.toDouble(),
      poster: json['poster'] as String?,
      backdrop: json['backdrop'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wireValue,
        'is_anime': isAnime,
        'title': title,
        if (originalTitle != null) 'original_title': originalTitle,
        if (overview != null) 'overview': overview,
        if (year != null) 'year': year,
        if (rating != null) 'rating': rating,
        if (poster != null) 'poster': poster,
        if (backdrop != null) 'backdrop': backdrop,
      };
}

class GenreOption {
  final String slug;
  final String label;

  const GenreOption({required this.slug, required this.label});

  factory GenreOption.fromJson(Map<String, dynamic> json) {
    return GenreOption(
      slug: json['slug']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }
}

class SeasonSummary {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? airDate;
  final String? poster;

  const SeasonSummary({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.airDate,
    this.poster,
  });

  factory SeasonSummary.fromJson(Map<String, dynamic> json) {
    return SeasonSummary(
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Stagione',
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      airDate: json['air_date'] as String?,
      poster: json['poster'] as String?,
    );
  }
}

class EpisodeDetail {
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? airDate;
  final int? runtime;
  final String? still;
  final bool watched;

  const EpisodeDetail({
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.airDate,
    this.runtime,
    this.still,
    this.watched = false,
  });

  EpisodeDetail copyWith({bool? watched}) {
    return EpisodeDetail(
      episodeNumber: episodeNumber,
      name: name,
      overview: overview,
      airDate: airDate,
      runtime: runtime,
      still: still,
      watched: watched ?? this.watched,
    );
  }

  factory EpisodeDetail.fromJson(Map<String, dynamic> json) {
    return EpisodeDetail(
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'Episodio',
      overview: json['overview'] as String?,
      airDate: json['air_date'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      still: json['still'] as String?,
      watched: json['watched'] as bool? ?? false,
    );
  }
}

class SeasonDetail {
  final int seasonNumber;
  final String name;
  final List<EpisodeDetail> episodes;

  const SeasonDetail({
    required this.seasonNumber,
    required this.name,
    required this.episodes,
  });

  factory SeasonDetail.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'] as List<dynamic>? ?? const [];
    return SeasonDetail(
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'Stagione',
      episodes: rawEpisodes
          .whereType<Map<String, dynamic>>()
          .map(EpisodeDetail.fromJson)
          .toList(),
    );
  }
}

class MediaDetail {
  final int id;
  final MediaKind kind;
  final bool isAnime;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? year;
  final double? rating;
  final String? status;
  final int? runtime;
  final List<String> genres;
  final String? poster;
  final String? backdrop;
  final List<SeasonSummary> seasons;
  final LibraryItemView? library;

  const MediaDetail({
    required this.id,
    required this.kind,
    required this.isAnime,
    required this.title,
    this.originalTitle,
    this.overview,
    this.year,
    this.rating,
    this.status,
    this.runtime,
    this.genres = const [],
    this.poster,
    this.backdrop,
    this.seasons = const [],
    this.library,
  });

  MediaSummary toSummary() => MediaSummary(
        id: id,
        kind: kind,
        isAnime: isAnime,
        title: title,
        originalTitle: originalTitle,
        overview: overview,
        year: year,
        rating: rating,
        poster: poster,
        backdrop: backdrop,
      );

  factory MediaDetail.fromJson(Map<String, dynamic> json) {
    return MediaDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: MediaKind.fromWire(json['kind'] as String?),
      isAnime: json['is_anime'] as bool? ?? false,
      title: json['title'] as String? ?? 'Titolo sconosciuto',
      originalTitle: json['original_title'] as String?,
      overview: json['overview'] as String?,
      year: parseYearField(json['year']),
      rating: (json['rating'] as num?)?.toDouble(),
      status: json['status'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      poster: json['poster'] as String?,
      backdrop: json['backdrop'] as String?,
      seasons: (json['seasons'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(SeasonSummary.fromJson)
              .toList() ??
          const [],
      library: json['library'] is Map<String, dynamic>
          ? LibraryItemView.fromJson(json['library'] as Map<String, dynamic>)
          : null,
    );
  }
}

class HlsTrackInfo {
  final String language;
  final String name;
  final String url;

  const HlsTrackInfo({
    required this.language,
    required this.name,
    required this.url,
  });

  factory HlsTrackInfo.fromJson(Map<String, dynamic> json) {
    return HlsTrackInfo(
      language: json['language']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Traccia',
      url: json['url']?.toString() ?? '',
    );
  }
}

class HlsVideoVariant {
  final String quality;
  final String? resolution;
  final int? bandwidth;
  final String url;

  const HlsVideoVariant({
    required this.quality,
    this.resolution,
    this.bandwidth,
    required this.url,
  });

  factory HlsVideoVariant.fromJson(Map<String, dynamic> json) {
    return HlsVideoVariant(
      quality: json['quality']?.toString() ?? 'auto',
      resolution: json['resolution']?.toString(),
      bandwidth: (json['bandwidth'] as num?)?.toInt(),
      url: json['url']?.toString() ?? '',
    );
  }
}

class HlsSource {
  final String source;
  final String playlistUrl;
  final String? referer;
  final List<HlsTrackInfo> audio;
  final List<HlsTrackInfo> subtitles;
  final List<HlsVideoVariant> video;

  const HlsSource({
    required this.source,
    required this.playlistUrl,
    this.referer,
    this.audio = const [],
    this.subtitles = const [],
    this.video = const [],
  });

  factory HlsSource.fromJson(Map<String, dynamic> json) {
    return HlsSource(
      source: json['source']?.toString() ?? 'hls',
      playlistUrl: json['playlist_url']?.toString() ?? '',
      referer: json['referer']?.toString(),
      audio: (json['audio'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(HlsTrackInfo.fromJson)
              .toList() ??
          const [],
      subtitles: (json['subtitles'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(HlsTrackInfo.fromJson)
              .toList() ??
          const [],
      video: (json['video'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(HlsVideoVariant.fromJson)
              .toList() ??
          const [],
    );
  }
}

class TorrentSource {
  final String title;
  final String? filename;
  final String infoHash;
  final String magnet;
  final String quality;
  final int seeders;
  final int? sizeBytes;
  final int? fileIdx;
  final List<String> languages;
  final String? sourceIndexer;
  final bool cached;
  final String streamUrl;

  const TorrentSource({
    required this.title,
    this.filename,
    required this.infoHash,
    required this.magnet,
    required this.quality,
    required this.seeders,
    this.sizeBytes,
    this.fileIdx,
    this.languages = const [],
    this.sourceIndexer,
    this.cached = false,
    required this.streamUrl,
  });

  String get displayName =>
      (filename != null && filename!.trim().isNotEmpty) ? filename! : title;

  String get formattedSize {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return '';
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }

  factory TorrentSource.fromJson(Map<String, dynamic> json) {
    return TorrentSource(
      title: json['title']?.toString() ?? 'Torrent',
      filename: json['filename']?.toString(),
      infoHash: json['info_hash']?.toString() ?? '',
      magnet: json['magnet']?.toString() ?? '',
      quality: json['quality']?.toString() ?? 'auto',
      seeders: (json['seeders'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      fileIdx: (json['file_idx'] as num?)?.toInt(),
      languages: (json['languages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sourceIndexer: json['source_indexer']?.toString(),
      cached: json['cached'] as bool? ?? false,
      streamUrl: json['stream_url']?.toString() ?? '',
    );
  }
}

class ResolvedStream {
  final int id;
  final MediaKind kind;
  final bool isAnime;
  final String title;
  final int? season;
  final int? episode;
  final String recommendedMode;
  final String recommendedUrl;
  final String? recommendedInfoHash;
  final HlsSource? hls;
  final List<TorrentSource> torrents;
  final NextEpisodeInfo? nextEpisode;

  const ResolvedStream({
    required this.id,
    required this.kind,
    required this.isAnime,
    required this.title,
    this.season,
    this.episode,
    required this.recommendedMode,
    required this.recommendedUrl,
    this.recommendedInfoHash,
    this.hls,
    this.torrents = const [],
    this.nextEpisode,
  });

  bool get isTorrentRecommended => recommendedMode == 'torrent';

  factory ResolvedStream.fromJson(Map<String, dynamic> json) {
    return ResolvedStream(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: MediaKind.fromWire(json['kind'] as String?),
      isAnime: json['is_anime'] as bool? ?? false,
      title: json['title'] as String? ?? 'Stream',
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      recommendedMode: json['recommended_mode']?.toString() ?? 'hls',
      recommendedUrl: json['recommended_url']?.toString() ?? '',
      recommendedInfoHash: json['recommended_info_hash']?.toString(),
      hls: json['hls'] is Map<String, dynamic>
          ? HlsSource.fromJson(json['hls'] as Map<String, dynamic>)
          : null,
      torrents: (json['torrents'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(TorrentSource.fromJson)
              .toList() ??
          const [],
      nextEpisode: json['next_episode'] is Map<String, dynamic>
          ? NextEpisodeInfo.fromJson(
              json['next_episode'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}
