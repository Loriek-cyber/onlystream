import 'package:onlystream/models/common.dart';

export 'package:onlystream/models/common.dart';

enum WatchStatus {
  watching('watching'),
  saved('saved'),
  completed('completed');

  const WatchStatus(this.wireValue);

  final String wireValue;

  static WatchStatus fromWire(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'watching':
        return WatchStatus.watching;
      case 'completed':
        return WatchStatus.completed;
      case 'saved':
      default:
        return WatchStatus.saved;
    }
  }
}

class EpisodeProgress {
  final int positionSecs;
  final int durationSecs;
  final String updatedAt;

  const EpisodeProgress({
    this.positionSecs = 0,
    this.durationSecs = 0,
    this.updatedAt = '',
  });

  double get progressRatio {
    if (durationSecs <= 0) return 0.0;
    return (positionSecs / durationSecs).clamp(0.0, 1.0);
  }

  factory EpisodeProgress.fromJson(Map<String, dynamic> json) {
    return EpisodeProgress(
      positionSecs: (json['position_secs'] as num?)?.round() ?? 0,
      durationSecs: (json['duration_secs'] as num?)?.round() ?? 0,
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'position_secs': positionSecs,
        'duration_secs': durationSecs,
        if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
      };
}

class LibraryItemView {
  final int id;
  final MediaKind kind;
  final bool isAnime;
  final String title;
  final String? poster;
  final String? backdrop;
  final String? year;
  final WatchStatus status;
  final int? currentSeason;
  final int? currentEpisode;
  final int positionSecs;
  final int durationSecs;
  final List<String> watchedEpisodes;
  final Map<String, EpisodeProgress> episodePositions;
  final String? preferredLang;
  final String updatedAt;
  final NextEpisodeInfo? nextEpisode;
  final bool hasNewEpisodes;
  final int newEpisodesCount;
  final int? latestAiredSeason;
  final int? latestAiredEpisode;

  const LibraryItemView({
    required this.id,
    required this.kind,
    required this.isAnime,
    required this.title,
    this.poster,
    this.backdrop,
    this.year,
    required this.status,
    this.currentSeason,
    this.currentEpisode,
    this.positionSecs = 0,
    this.durationSecs = 0,
    this.watchedEpisodes = const [],
    this.episodePositions = const {},
    this.preferredLang,
    this.updatedAt = '',
    this.nextEpisode,
    this.hasNewEpisodes = false,
    this.newEpisodesCount = 0,
    this.latestAiredSeason,
    this.latestAiredEpisode,
  });

  static String episodeKey(int season, int episode) =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  String get key => '${kind.wireValue}:$id';

  double get progressRatio {
    if (durationSecs <= 0) return 0.0;
    return (positionSecs / durationSecs).clamp(0.0, 1.0);
  }

  String? get episodeLabel {
    if (kind != MediaKind.tv) return null;
    final season = currentSeason ?? nextEpisode?.season;
    final episode = currentEpisode ?? nextEpisode?.episode;
    if (season == null || episode == null) return null;
    return 'S$season · E$episode';
  }

  EpisodeProgress? progressForEpisode(int season, int episode) {
    final direct = episodePositions[episodeKey(season, episode)];
    if (direct != null) return direct;
    final padded =
        'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
    final fromPadded = episodePositions[padded];
    if (fromPadded != null) return fromPadded;
    for (final entry in episodePositions.entries) {
      final lower = entry.key.trim().toLowerCase();
      if (lower == 's${season}e$episode' || lower == padded.toLowerCase()) {
        return entry.value;
      }
    }
    if (currentSeason == season &&
        currentEpisode == episode &&
        positionSecs > 0) {
      return EpisodeProgress(
        positionSecs: positionSecs,
        durationSecs: durationSecs,
        updatedAt: updatedAt,
      );
    }
    return null;
  }

  int positionForEpisode(int season, int episode) =>
      progressForEpisode(season, episode)?.positionSecs ?? 0;

  bool isEpisodeWatched(int season, int episode) {
    final candidates = {
      's${season}e$episode',
      's${season.toString().padLeft(2, '0')}e${episode.toString().padLeft(2, '0')}',
      '$season:$episode',
      '${season}x$episode',
    };
    return watchedEpisodes.any(
      (entry) => candidates.contains(entry.trim().toLowerCase()),
    );
  }

  LibraryItemView copyWith({
    int? id,
    MediaKind? kind,
    bool? isAnime,
    String? title,
    String? poster,
    String? backdrop,
    String? year,
    WatchStatus? status,
    int? currentSeason,
    int? currentEpisode,
    int? positionSecs,
    int? durationSecs,
    List<String>? watchedEpisodes,
    Map<String, EpisodeProgress>? episodePositions,
    String? preferredLang,
    String? updatedAt,
    NextEpisodeInfo? nextEpisode,
    bool? hasNewEpisodes,
    int? newEpisodesCount,
    int? latestAiredSeason,
    int? latestAiredEpisode,
  }) {
    return LibraryItemView(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      isAnime: isAnime ?? this.isAnime,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      backdrop: backdrop ?? this.backdrop,
      year: year ?? this.year,
      status: status ?? this.status,
      currentSeason: currentSeason ?? this.currentSeason,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      positionSecs: positionSecs ?? this.positionSecs,
      durationSecs: durationSecs ?? this.durationSecs,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
      episodePositions: episodePositions ?? this.episodePositions,
      preferredLang: preferredLang ?? this.preferredLang,
      updatedAt: updatedAt ?? this.updatedAt,
      nextEpisode: nextEpisode ?? this.nextEpisode,
      hasNewEpisodes: hasNewEpisodes ?? this.hasNewEpisodes,
      newEpisodesCount: newEpisodesCount ?? this.newEpisodesCount,
      latestAiredSeason: latestAiredSeason ?? this.latestAiredSeason,
      latestAiredEpisode: latestAiredEpisode ?? this.latestAiredEpisode,
    );
  }

  factory LibraryItemView.fromJson(Map<String, dynamic> json) {
    final rawEpPositions = json['episode_positions'];
    final parsedEpPositions = <String, EpisodeProgress>{};
    if (rawEpPositions is Map) {
      for (final entry in rawEpPositions.entries) {
        if (entry.value is Map<String, dynamic>) {
          parsedEpPositions[entry.key.toString()] =
              EpisodeProgress.fromJson(entry.value as Map<String, dynamic>);
        } else if (entry.value is Map) {
          parsedEpPositions[entry.key.toString()] = EpisodeProgress.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    return LibraryItemView(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: MediaKind.fromWire(json['kind'] as String?),
      isAnime: json['is_anime'] as bool? ?? false,
      title: json['title'] as String? ?? 'Titolo sconosciuto',
      poster: json['poster'] as String?,
      backdrop: json['backdrop'] as String?,
      year: parseYearField(json['year']),
      status: WatchStatus.fromWire(json['status'] as String?),
      currentSeason: (json['current_season'] as num?)?.toInt(),
      currentEpisode: (json['current_episode'] as num?)?.toInt(),
      positionSecs: (json['position_secs'] as num?)?.round() ?? 0,
      durationSecs: (json['duration_secs'] as num?)?.round() ?? 0,
      watchedEpisodes: (json['watched_episodes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      episodePositions: parsedEpPositions,
      preferredLang: json['preferred_lang'] as String?,
      updatedAt: json['updated_at']?.toString() ?? '',
      nextEpisode: json['next_episode'] is Map<String, dynamic>
          ? NextEpisodeInfo.fromJson(
              json['next_episode'] as Map<String, dynamic>,
            )
          : null,
      hasNewEpisodes: json['has_new_episodes'] as bool? ?? false,
      newEpisodesCount: (json['new_episodes_count'] as num?)?.toInt() ?? 0,
      latestAiredSeason: (json['latest_aired_season'] as num?)?.toInt(),
      latestAiredEpisode: (json['latest_aired_episode'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wireValue,
        'is_anime': isAnime,
        'title': title,
        if (poster != null) 'poster': poster,
        if (backdrop != null) 'backdrop': backdrop,
        if (year != null) 'year': year,
        'status': status.wireValue,
        if (currentSeason != null) 'current_season': currentSeason,
        if (currentEpisode != null) 'current_episode': currentEpisode,
        'position_secs': positionSecs,
        'duration_secs': durationSecs,
        'watched_episodes': watchedEpisodes,
        'episode_positions': episodePositions.map(
          (k, v) => MapEntry(k, v.toJson()),
        ),
        if (preferredLang != null) 'preferred_lang': preferredLang,
        'updated_at': updatedAt,
        if (nextEpisode != null) 'next_episode': nextEpisode!.toJson(),
        'has_new_episodes': hasNewEpisodes,
        'new_episodes_count': newEpisodesCount,
        if (latestAiredSeason != null) 'latest_aired_season': latestAiredSeason,
        if (latestAiredEpisode != null)
          'latest_aired_episode': latestAiredEpisode,
      };
}

class LibrarySnapshot {
  final List<LibraryItemView> continueWatching;
  final List<LibraryItemView> saved;
  final List<LibraryItemView> completed;
  final List<LibraryItemView> items;

  const LibrarySnapshot({
    this.continueWatching = const [],
    this.saved = const [],
    this.completed = const [],
    this.items = const [],
  });

  static const LibrarySnapshot empty = LibrarySnapshot();

  factory LibrarySnapshot.fromJson(Map<String, dynamic> json) {
    List<LibraryItemView> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(LibraryItemView.fromJson)
          .toList();
    }

    return LibrarySnapshot(
      continueWatching: parseList(json['continue_watching']),
      saved: parseList(json['saved']),
      completed: parseList(json['completed']),
      items: parseList(json['items']),
    );
  }

  factory LibrarySnapshot.fromItems(List<LibraryItemView> allItems) {
    final sorted = List<LibraryItemView>.from(allItems)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return LibrarySnapshot(
      continueWatching: sorted
          .where((item) => item.status == WatchStatus.watching)
          .toList(),
      saved: sorted.where((item) => item.status == WatchStatus.saved).toList(),
      completed: sorted
          .where((item) => item.status == WatchStatus.completed)
          .toList(),
      items: sorted,
    );
  }

  Map<String, dynamic> toJson() => {
        'continue_watching': continueWatching.map((e) => e.toJson()).toList(),
        'saved': saved.map((e) => e.toJson()).toList(),
        'completed': completed.map((e) => e.toJson()).toList(),
        'items': items.map((e) => e.toJson()).toList(),
      };
}
