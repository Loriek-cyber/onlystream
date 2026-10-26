import 'package:flutter/material.dart';
import 'package:onlystream/utils/constants.dart';

/// Unified Quality enum matching `easystreamapi/src/models/quality.rs`.
enum Quality {
  unknown('unknown', 0),
  sd('sd', 1),
  p480('480p', 2),
  p720('720p', 3),
  p1080('1080p', 4),
  p1440('1440p', 5),
  p2160('2160p', 6);

  final String label;
  final int rank;
  const Quality(this.label, this.rank);

  static Quality fromLabel(String? raw) {
    if (raw == null || raw.trim().isEmpty) return Quality.unknown;
    final l = raw.trim().toLowerCase();
    switch (l) {
      case '2160p':
      case '2160':
      case '4k':
      case 'uhd':
      case '4kuhd':
        return Quality.p2160;
      case '1440p':
      case '1440':
      case '2k':
      case 'qhd':
        return Quality.p1440;
      case '1080p':
      case '1080':
      case '1080i':
      case 'fhd':
      case 'fullhd':
        return Quality.p1080;
      case '720p':
      case '720':
      case 'hd':
        return Quality.p720;
      case '480p':
      case '480':
      case '576p':
      case '576':
        return Quality.p480;
      case 'sd':
      case '360p':
      case '240p':
      case 'dvdrip':
      case 'cam':
        return Quality.sd;
      default:
        if (l.contains('2160') || l.contains('4k')) return Quality.p2160;
        if (l.contains('1440')) return Quality.p1440;
        if (l.contains('1080')) return Quality.p1080;
        if (l.contains('720')) return Quality.p720;
        if (l.contains('480')) return Quality.p480;
        return Quality.unknown;
    }
  }

  String get displayBadge {
    switch (this) {
      case Quality.p2160:
        return '4K UHD';
      case Quality.p1440:
        return '2K QHD';
      case Quality.p1080:
        return '1080p FHD';
      case Quality.p720:
        return '720p HD';
      case Quality.p480:
        return '480p';
      case Quality.sd:
        return 'SD';
      case Quality.unknown:
        return 'AUTO';
    }
  }

  Color get badgeColor {
    switch (this) {
      case Quality.p2160:
        return const Color(0xFFF59E0B);
      case Quality.p1440:
        return const Color(0xFFA855F7);
      case Quality.p1080:
        return const Color(0xFF06B6D4);
      case Quality.p720:
        return const Color(0xFF3B82F6);
      case Quality.p480:
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF64748B);
    }
  }
}

/// MediaKind matching `easystreamapi/src/models/media.rs`.
enum MediaKind {
  movie('movie'),
  tv('tv'),
  anime('anime');

  final String value;
  const MediaKind(this.value);

  static MediaKind fromString(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'tv' || s == 'series') return MediaKind.tv;
    if (s == 'anime') return MediaKind.anime;
    return MediaKind.movie;
  }

  String get labelIt {
    switch (this) {
      case MediaKind.movie:
        return 'FILM';
      case MediaKind.tv:
        return 'SERIE TV';
      case MediaKind.anime:
        return 'ANIME';
    }
  }
}

/// Unified Search Result combining `TmdbSearchResult` and `AnimeRecord` from easystreamapi.
class UnifiedSearchResult {
  final int id;
  final String title;
  final String? originalTitle;
  final MediaKind mediaKind;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
  final String? releaseDate;
  final double? voteAverage;
  final int? episodesCount;
  final String? status;
  final bool? isDubbedIta;
  final String? animeType;

  const UnifiedSearchResult({
    required this.id,
    required this.title,
    this.originalTitle,
    required this.mediaKind,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.releaseDate,
    this.voteAverage,
    this.episodesCount,
    this.status,
    this.isDubbedIta,
    this.animeType,
  });

  String get year {
    if (releaseDate == null || releaseDate!.isEmpty) return '';
    return releaseDate!.length >= 4 ? releaseDate!.substring(0, 4) : releaseDate!;
  }

  factory UnifiedSearchResult.fromTmdbJson(Map<String, dynamic> json) {
    final rawPosterPath = json['poster_path'] as String?;
    final rawPosterUrl = json['poster_url'] as String?;
    final poster = (rawPosterUrl != null && rawPosterUrl.isNotEmpty)
        ? rawPosterUrl
        : (rawPosterPath != null && rawPosterPath.isNotEmpty
            ? 'https://image.tmdb.org/t/p/w500$rawPosterPath'
            : null);

    final rawBackdropPath = json['backdrop_path'] as String?;
    final rawBackdropUrl = json['backdrop_url'] as String?;
    final backdrop = (rawBackdropUrl != null && rawBackdropUrl.isNotEmpty)
        ? rawBackdropUrl
        : (rawBackdropPath != null && rawBackdropPath.isNotEmpty
            ? 'https://image.tmdb.org/t/p/w1280$rawBackdropPath'
            : null);

    final mediaTypeStr = json['media_type'] as String? ??
        (json['name'] != null || json['first_air_date'] != null ? 'tv' : 'movie');

    return UnifiedSearchResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? json['name'] ?? json['original_title'] ?? 'Senza titolo')
          .toString(),
      originalTitle: (json['original_title'] ?? json['original_name']) as String?,
      mediaKind: MediaKind.fromString(mediaTypeStr),
      overview: json['overview'] as String?,
      posterUrl: poster,
      backdropUrl: backdrop,
      releaseDate: (json['release_date'] ?? json['first_air_date']) as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
    );
  }

  factory UnifiedSearchResult.fromAnimeJson(Map<String, dynamic> json) {
    final title = (json['title_it'] ?? json['title'] ?? json['title_eng'] ?? 'Senza titolo')
        .toString();
    final dubVal = (json['dub'] as num?)?.toInt();
    final isIta = dubVal == 1 || title.toLowerCase().contains('(ita)');
    return UnifiedSearchResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: title,
      originalTitle: (json['title'] ?? json['title_eng']) as String?,
      mediaKind: MediaKind.anime,
      overview: json['plot'] as String?,
      posterUrl: json['imageurl'] as String?,
      backdropUrl: json['imageurl'] as String?,
      releaseDate: json['date']?.toString(),
      episodesCount: (json['episodes_count'] as num?)?.toInt(),
      status: json['status'] as String?,
      isDubbedIta: isIta,
      animeType: json['type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'original_title': originalTitle,
        'media_type': mediaKind.value,
        'overview': overview,
        'poster_url': posterUrl,
        'backdrop_url': backdropUrl,
        'release_date': releaseDate,
        'vote_average': voteAverage,
        'episodes_count': episodesCount,
        'status': status,
        'dub': isDubbedIta == true ? 1 : 0,
        'type': animeType,
      };
}

/// TorrentItem matching `easystreamapi/src/models/torrent.rs`.
class TorrentItem {
  final String title;
  final String? filename;
  final String infoHash;
  final String magnet;
  final Quality quality;
  final int seeders;
  final int? sizeBytes;
  final int? folderSizeBytes;
  final int? fileIdx;
  final List<String> languages;
  final List<String> trackers;
  final String? sourceIndexer;
  final bool cached;

  const TorrentItem({
    required this.title,
    this.filename,
    required this.infoHash,
    required this.magnet,
    required this.quality,
    required this.seeders,
    this.sizeBytes,
    this.folderSizeBytes,
    this.fileIdx,
    this.languages = const [],
    this.trackers = const [],
    this.sourceIndexer,
    this.cached = false,
  });

  factory TorrentItem.fromJson(Map<String, dynamic> json) {
    return TorrentItem(
      title: json['title'] as String? ?? 'Torrent',
      filename: json['filename'] as String?,
      infoHash: json['info_hash'] as String? ?? '',
      magnet: json['magnet'] as String? ?? '',
      quality: Quality.fromLabel(json['quality']?.toString()),
      seeders: (json['seeders'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      folderSizeBytes: (json['folder_size_bytes'] as num?)?.toInt(),
      fileIdx: (json['file_idx'] as num?)?.toInt(),
      languages: (json['languages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      trackers: (json['trackers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sourceIndexer: json['source_indexer'] as String?,
      cached: json['cached'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'filename': filename,
        'info_hash': infoHash,
        'magnet': magnet,
        'quality': quality.label,
        'seeders': seeders,
        'size_bytes': sizeBytes,
        'folder_size_bytes': folderSizeBytes,
        'file_idx': fileIdx,
        'languages': languages,
        'trackers': trackers,
        'source_indexer': sourceIndexer,
        'cached': cached,
      };

  String get formattedSize {
    final bytes = sizeBytes ?? folderSizeBytes;
    if (bytes == null || bytes <= 0) return 'N/D';
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}

/// Stream tracks & info matching `easystreamapi/src/models/stream.rs`.
class ApiAudioTrack {
  final String language;
  final String name;
  final String url;

  const ApiAudioTrack({
    required this.language,
    required this.name,
    required this.url,
  });

  factory ApiAudioTrack.fromJson(Map<String, dynamic> json) => ApiAudioTrack(
        language: json['language'] as String? ?? '',
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class ApiSubtitleTrack {
  final String language;
  final String name;
  final String url;

  const ApiSubtitleTrack({
    required this.language,
    required this.name,
    required this.url,
  });

  factory ApiSubtitleTrack.fromJson(Map<String, dynamic> json) =>
      ApiSubtitleTrack(
        language: json['language'] as String? ?? '',
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class ApiVideoTrack {
  final Quality quality;
  final String? resolution;
  final int? bandwidth;
  final String url;

  const ApiVideoTrack({
    required this.quality,
    this.resolution,
    this.bandwidth,
    required this.url,
  });

  factory ApiVideoTrack.fromJson(Map<String, dynamic> json) => ApiVideoTrack(
        quality: Quality.fromLabel(json['quality']?.toString()),
        resolution: json['resolution'] as String?,
        bandwidth: (json['bandwidth'] as num?)?.toInt(),
        url: json['url'] as String? ?? '',
      );
}

class StreamInfo {
  final String title;
  final String source;
  final String playlistUrl;
  final String? embedUrl;
  final String m3u8Content;
  final List<ApiAudioTrack> audio;
  final List<ApiSubtitleTrack> subtitles;
  final List<ApiVideoTrack> video;
  final List<TorrentItem> torrents;

  const StreamInfo({
    required this.title,
    required this.source,
    required this.playlistUrl,
    this.embedUrl,
    required this.m3u8Content,
    this.audio = const [],
    this.subtitles = const [],
    this.video = const [],
    this.torrents = const [],
  });

  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    return StreamInfo(
      title: json['title'] as String? ?? 'Stream',
      source: json['source'] as String? ?? 'auto',
      playlistUrl: json['playlist_url'] as String? ?? '',
      embedUrl: json['embed_url'] as String?,
      m3u8Content: json['m3u8_content'] as String? ?? '',
      audio: (json['audio'] as List<dynamic>?)
              ?.map((e) => ApiAudioTrack.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      subtitles: (json['subtitles'] as List<dynamic>?)
              ?.map((e) => ApiSubtitleTrack.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      video: (json['video'] as List<dynamic>?)
              ?.map((e) => ApiVideoTrack.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      torrents: (json['torrents'] as List<dynamic>?)
              ?.map((e) => TorrentItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// Download package & media matching `easystreamapi/src/models/download.rs`.
class DownloadPackage {
  final String uri;
  final Quality quality;
  final List<ApiAudioTrack> audio;
  final List<ApiSubtitleTrack> subtitles;
  final int number;
  final String? label;
  final int? bandwidth;

  const DownloadPackage({
    required this.uri,
    required this.quality,
    this.audio = const [],
    this.subtitles = const [],
    required this.number,
    this.label,
    this.bandwidth,
  });

  factory DownloadPackage.fromJson(Map<String, dynamic> json) => DownloadPackage(
        uri: json['uri'] as String? ?? '',
        quality: Quality.fromLabel(json['quality']?.toString()),
        audio: (json['audio'] as List<dynamic>?)
                ?.map((e) => ApiAudioTrack.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        subtitles: (json['subtitles'] as List<dynamic>?)
                ?.map(
                    (e) => ApiSubtitleTrack.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        number: (json['number'] as num?)?.toInt() ?? 0,
        label: json['label'] as String?,
        bandwidth: (json['bandwidth'] as num?)?.toInt(),
      );
}

class DownloadMediaInfo {
  final MediaKind mediaType;
  final Map<String, dynamic>? mediaRaw;
  final String? masterPlaylistUrl;
  final List<DownloadPackage> packages;
  final List<TorrentItem> torrents;
  final String? referer;

  const DownloadMediaInfo({
    required this.mediaType,
    this.mediaRaw,
    this.masterPlaylistUrl,
    this.packages = const [],
    this.torrents = const [],
    this.referer,
  });

  factory DownloadMediaInfo.fromJson(Map<String, dynamic> json) {
    return DownloadMediaInfo(
      mediaType: MediaKind.fromString(json['media_type']?.toString()),
      mediaRaw: json['media'] as Map<String, dynamic>?,
      masterPlaylistUrl: json['master_playlist_url'] as String?,
      packages: (json['packages'] as List<dynamic>?)
              ?.map((e) => DownloadPackage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      torrents: (json['torrents'] as List<dynamic>?)
              ?.map((e) => TorrentItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      referer: json['referer'] as String?,
    );
  }

  String get title {
    if (mediaRaw == null) return 'Download';
    return (mediaRaw!['title'] ?? mediaRaw!['name'] ?? 'Download').toString();
  }

  String? get overview => mediaRaw?['overview'] as String?;

  String? get posterUrl {
    final p = mediaRaw?['poster_path'] as String?;
    if (p != null && p.isNotEmpty) return 'https://image.tmdb.org/t/p/w500$p';
    return null;
  }

  String? get backdropUrl {
    final p = mediaRaw?['backdrop_path'] as String?;
    if (p != null && p.isNotEmpty) return 'https://image.tmdb.org/t/p/w1280$p';
    return null;
  }

  List<TvSeasonSummary> get seasons {
    final list = mediaRaw?['seasons'] as List<dynamic>?;
    if (list == null) return const [];
    return list
        .map((e) => TvSeasonSummary.fromJson(e as Map<String, dynamic>))
        .where((s) => s.seasonNumber > 0 && s.episodeCount > 0)
        .toList();
  }
}

class TvSeasonSummary {
  final int id;
  final String name;
  final int seasonNumber;
  final int episodeCount;
  final String? posterPath;
  final String? airDate;

  const TvSeasonSummary({
    required this.id,
    required this.name,
    required this.seasonNumber,
    required this.episodeCount,
    this.posterPath,
    this.airDate,
  });

  factory TvSeasonSummary.fromJson(Map<String, dynamic> json) => TvSeasonSummary(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Stagione',
        seasonNumber: (json['season_number'] as num?)?.toInt() ?? 1,
        episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
        posterPath: json['poster_path'] as String?,
        airDate: json['air_date'] as String?,
      );
}

/// Anime episodes response matching `easystreamapi/src/models/anime/mod.rs`.
class AnimeEpisodeItem {
  final int id;
  final String number;
  final int? scwsId;
  final String? fileName;

  const AnimeEpisodeItem({
    required this.id,
    required this.number,
    this.scwsId,
    this.fileName,
  });

  int get episodeNumber => int.tryParse(number) ?? 1;

  factory AnimeEpisodeItem.fromJson(Map<String, dynamic> json) =>
      AnimeEpisodeItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        number: json['number']?.toString() ?? '1',
        scwsId: (json['scws_id'] as num?)?.toInt(),
        fileName: json['file_name'] as String?,
      );
}

class AnimeEpisodesResponse {
  final int episodesCount;
  final int? currentEpisode;
  final List<AnimeEpisodeItem> episodes;

  const AnimeEpisodesResponse({
    required this.episodesCount,
    this.currentEpisode,
    this.episodes = const [],
  });

  factory AnimeEpisodesResponse.fromJson(Map<String, dynamic> json) =>
      AnimeEpisodesResponse(
        episodesCount: (json['episodes_count'] as num?)?.toInt() ?? 0,
        currentEpisode: (json['current_episode'] as num?)?.toInt(),
        episodes: (json['episodes'] as List<dynamic>?)
                ?.map(
                    (e) => AnimeEpisodeItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// Offload FFmpeg command response (`?download=cmd`).
class DownloadCommandInfo {
  final String title;
  final String filename;
  final String? quality;
  final String playlistUrl;
  final String? audioUrl;
  final String command;
  final String description;

  const DownloadCommandInfo({
    required this.title,
    required this.filename,
    this.quality,
    required this.playlistUrl,
    this.audioUrl,
    required this.command,
    required this.description,
  });

  factory DownloadCommandInfo.fromJson(Map<String, dynamic> json) =>
      DownloadCommandInfo(
        title: json['title'] as String? ?? '',
        filename: json['filename'] as String? ?? 'video.mp4',
        quality: json['quality'] as String?,
        playlistUrl: json['playlist_url'] as String? ?? '',
        audioUrl: json['audio_url'] as String?,
        command: json['command'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}

// ── Backwards-Compatible Video Player Models ──────────────────────────

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

  Map<String, dynamic> toJson() => {
        'season': season,
        'number': number,
        'title': title,
      };

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        season: (json['season'] as num?)?.toInt() ?? 1,
        number: (json['number'] as num?)?.toInt() ?? 1,
        title: json['title'] as String?,
      );
}

// [Video_Model]
class Video {
  final int id;
  final String title;
  final String type; // "movie", "series", "anime"
  final List<AudioTrack> audioTracks;
  final Episode? currentEpisode;
  final Episode? nextEpisode;
  final bool hasNext;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final String? localFilePath;
  final String? directStreamUrl;

  Video({
    required this.id,
    required this.title,
    required this.type,
    this.audioTracks = const [],
    this.currentEpisode,
    this.nextEpisode,
    this.hasNext = false,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.localFilePath,
    this.directStreamUrl,
  });

  bool get isSeries => type == 'series' || type == 'tv';
  bool get isAnime => type == 'anime';
  bool get isMovie => type == 'movie';

  // Factory constructor for parsing API response (`EpisodeNavigationResponse`)
  factory Video.fromJson(Map<String, dynamic> json) {
    final mediaType = json['media_type'] as String? ?? 'movie';
    final isTv = mediaType == 'tv' || mediaType == 'series';
    final isAnime = mediaType == 'anime';
    final hasNext = json['has_next'] as bool? ?? false;

    final season =
        (json['season'] as num?)?.toInt() ??
        (json['current_season'] as num?)?.toInt() ??
        1;
    final episodeNum =
        (json['episode'] as num?)?.toInt() ??
        (json['current_episode'] as num?)?.toInt() ??
        1;
    final episodeTitle =
        json['episode_name'] as String? ?? json['episode_title'] as String?;

    final nextSeason = (json['next_season'] as num?)?.toInt() ?? (isAnime ? 1 : null);
    final nextEpNum = (json['next_episode'] as num?)?.toInt();
    final nextEpTitle = json['next_episode_title'] as String?;

    final resolvedId = (json['tmdb_id'] as num?)?.toInt() ??
        (json['anime_id'] as num?)?.toInt() ??
        (json['id'] as num?)?.toInt() ??
        0;

    return Video(
      id: resolvedId,
      title: json['series_name'] as String? ??
          json['title'] as String? ??
          'Unknown',
      type: isAnime ? 'anime' : (isTv ? 'series' : mediaType),
      audioTracks: [],
      currentEpisode: (isTv || isAnime)
          ? Episode(season: season, number: episodeNum, title: episodeTitle)
          : null,
      nextEpisode: (isTv || isAnime) && hasNext && nextEpNum != null
          ? Episode(
              season: nextSeason ?? season,
              number: nextEpNum,
              title: nextEpTitle,
            )
          : null,
      hasNext: hasNext,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      overview: json['overview'] as String?,
      localFilePath: json['local_file_path'] as String?,
      directStreamUrl: json['direct_stream_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'tmdb_id': id,
        'series_name': title,
        'media_type': type,
        'season': currentEpisode?.season,
        'episode': currentEpisode?.number,
        'episode_name': currentEpisode?.title,
        'next_season': nextEpisode?.season,
        'next_episode': nextEpisode?.number,
        'has_next': hasNext,
        'poster_url': posterUrl,
        'backdrop_url': backdropUrl,
        'overview': overview,
        'local_file_path': localFilePath,
        'direct_stream_url': directStreamUrl,
      };

  /// Construct the M3U8/HLS stream URL using the dynamic server URL.
  String getStreamUrl({
    String language = 'it',
    String? quality,
    String? source,
    String? baseUrlOverride,
  }) {
    if (localFilePath != null && localFilePath!.isNotEmpty) {
      return localFilePath!;
    }
    if (directStreamUrl != null && directStreamUrl!.isNotEmpty) {
      return directStreamUrl!;
    }

    final base = baseUrlOverride ?? AppConstants.baseUrl;
    final queryParams = <String, String>{
      'lang': language,
      if (quality != null && quality.isNotEmpty && quality != 'auto')
        'quality': quality,
      if (source != null && source.isNotEmpty && source != 'auto')
        'source': source,
    };
    final queryString = queryParams.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    if (type == 'movie') {
      return '$base/movie/$id/?$queryString';
    } else if (type == 'anime') {
      final episode = currentEpisode?.number ?? 1;
      return '$base/anime/$id/$episode/?$queryString';
    } else {
      final season = currentEpisode?.season ?? 1;
      final episode = currentEpisode?.number ?? 1;
      return '$base/tv/$id/$season/$episode/?$queryString';
    }
  }

  /// Construct the direct MP4 download URL from the server (`?download=true`).
  String getDownloadMp4Url({
    String language = 'it',
    String? quality,
    String? baseUrlOverride,
  }) {
    final base = baseUrlOverride ?? AppConstants.baseUrl;
    final qParam =
        (quality != null && quality.isNotEmpty && quality != 'auto')
            ? '&quality=$quality'
            : '';
    if (type == 'movie') {
      return '$base/movie/$id/?download=true&lang=$language$qParam';
    } else if (type == 'anime') {
      final episode = currentEpisode?.number ?? 1;
      return '$base/anime/$id/$episode/?download=true&lang=$language$qParam';
    } else {
      final season = currentEpisode?.season ?? 1;
      final episode = currentEpisode?.number ?? 1;
      return '$base/tv/$id/$season/$episode/?download=true&lang=$language$qParam';
    }
  }

  /// Helper method: get next episode stream URL.
  String? getNextStreamUrl({String language = 'it'}) {
    if (!hasNext || nextEpisode == null) return null;
    final base = AppConstants.baseUrl;
    final season = nextEpisode!.season;
    final episode = nextEpisode!.number;
    if (type == 'anime') {
      return '$base/anime/$id/$episode/?lang=$language';
    }
    return '$base/tv/$id/$season/$episode/?lang=$language';
  }
}
