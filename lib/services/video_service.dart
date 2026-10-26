import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:onlystream/models/video_model.dart';
import 'package:onlystream/utils/constants.dart';

// [Video_Service]
class VideoService {
  static String get _base => AppConstants.baseUrl;

  /// Search TMDB via `/tmdb/search?q=...` (or `/movie/search`, `/tv/search`).
  static Future<List<UnifiedSearchResult>> searchTmdb({
    required String query,
    String? mediaType, // null/'all', 'movie', 'tv'
    String language = 'it',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    String endpoint = '/tmdb/search';
    if (mediaType == 'movie') endpoint = '/movie/search';
    if (mediaType == 'tv') endpoint = '/tv/search';

    final uri = Uri.parse('$_base$endpoint').replace(
      queryParameters: {
        'q': trimmed,
        'lang': language,
        if (mediaType != null && mediaType != 'all') 'type': mediaType,
      },
    );

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<dynamic> rawList = decoded is List
            ? decoded
            : (decoded is Map && decoded['results'] is List
                ? decoded['results'] as List<dynamic>
                : const []);
        return rawList
            .whereType<Map<String, dynamic>>()
            .where((m) => m['media_type'] != 'person')
            .map(UnifiedSearchResult.fromTmdbJson)
            .where((item) => item.id > 0)
            .toList();
      }
    } catch (e) {
      debugPrint('[VideoService] searchTmdb error: $e');
    }
    return const [];
  }

  /// Search AnimeUnity via `/anime/search?q=...`.
  static Future<List<UnifiedSearchResult>> searchAnime({
    required String query,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = Uri.parse('$_base/anime/search').replace(
      queryParameters: {'q': trimmed},
    );

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map(UnifiedSearchResult.fromAnimeJson)
              .where((item) => item.id > 0)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[VideoService] searchAnime error: $e');
    }
    return const [];
  }

  /// Unified search across TMDB (Movies + TV) and AnimeUnity simultaneously.
  static Future<List<UnifiedSearchResult>> searchAll({
    required String query,
    String filter = 'all', // 'all', 'movie', 'tv', 'anime'
    String language = 'it',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // Direct ID or IMDb tt... lookup support!
    if (RegExp(r'^(tt\d+|\d+)$', caseSensitive: false).hasMatch(trimmed)) {
      final isImdb = trimmed.toLowerCase().startsWith('tt');
      final numericId = int.tryParse(trimmed.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (!isImdb && numericId > 0) {
        final directResults = <UnifiedSearchResult>[];
        if (filter == 'all' || filter == 'movie') {
          final movieNav = await fetchMovieInfo(tmdbId: numericId, language: language);
          if (movieNav != null && movieNav.title != 'Unknown') {
            directResults.add(
              UnifiedSearchResult(
                id: numericId,
                title: movieNav.title,
                mediaKind: MediaKind.movie,
                overview: 'Ricerca diretta tramite ID TMDB #$numericId',
              ),
            );
          }
        }
        if (filter == 'all' || filter == 'tv') {
          final tvNav = await fetchCurrentEpisode(
            tvId: numericId,
            season: 1,
            episode: 1,
            language: language,
          );
          if (tvNav != null && tvNav.title != 'Unknown') {
            directResults.add(
              UnifiedSearchResult(
                id: numericId,
                title: tvNav.title,
                mediaKind: MediaKind.tv,
                overview: 'Ricerca diretta tramite ID TMDB #$numericId',
              ),
            );
          }
        }
        if (directResults.isNotEmpty) return directResults;
      }
    }

    if (filter == 'anime') {
      return searchAnime(query: trimmed);
    }
    if (filter == 'movie' || filter == 'tv') {
      return searchTmdb(
        query: trimmed,
        mediaType: filter,
        language: language,
      );
    }

    // Parallel TMDB + AnimeUnity search
    final results = await Future.wait([
      searchTmdb(query: trimmed, language: language),
      searchAnime(query: trimmed),
    ]);

    return [...results[0], ...results[1]];
  }

  /// Fetch full `StreamInfo` (`?format=json&torrents=true`) for a Movie, TV Episode, or Anime Episode.
  static Future<StreamInfo?> fetchStreamInfo({
    required MediaKind kind,
    required int id,
    int season = 1,
    int episode = 1,
    String language = 'it',
    String? quality,
    String? source,
    bool includeTorrents = true,
  }) async {
    final path = switch (kind) {
      MediaKind.movie => '/movie/$id/',
      MediaKind.tv => '/tv/$id/$season/$episode/',
      MediaKind.anime => '/anime/$id/$episode/',
    };

    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        'format': 'json',
        'lang': language,
        if (includeTorrents && kind != MediaKind.anime) 'torrents': 'true',
        if (quality != null && quality.isNotEmpty && quality != 'auto')
          'quality': quality,
        if (source != null && source.isNotEmpty && source != 'auto')
          'source': source,
      },
    );

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return StreamInfo.fromJson(data);
      }
    } catch (e) {
      debugPrint('[VideoService] fetchStreamInfo error: $e');
    }
    return null;
  }

  /// Fetch rich `DownloadMediaInfo` (`?download_data=true&torrents=true`) which includes
  /// full TMDB Movie/TvShow metadata (seasons, genres, overview), HLS packages, and torrents!
  static Future<DownloadMediaInfo?> fetchDownloadData({
    required MediaKind kind,
    required int id,
    int season = 1,
    int episode = 1,
    String language = 'it',
    bool includeTorrents = true,
  }) async {
    final path = switch (kind) {
      MediaKind.movie => '/movie/$id/',
      MediaKind.tv => '/tv/$id/$season/$episode/',
      MediaKind.anime => '/anime/$id/$episode/',
    };

    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        'download_data': 'true',
        'lang': language,
        if (includeTorrents && kind != MediaKind.anime) 'torrents': 'true',
      },
    );

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return DownloadMediaInfo.fromJson(data);
      }
    } catch (e) {
      debugPrint('[VideoService] fetchDownloadData error: $e');
    }
    return null;
  }

  /// Fetch dedicated torrents list from `/torrent/movie/{id}` or `/torrent/tv/{id}/{s}/{e}`.
  static Future<List<TorrentItem>> fetchTorrents({
    required MediaKind kind,
    required String rawId, // Supports TMDB numeric ID or IMDb 'tt...'
    int season = 1,
    int episode = 1,
    String language = 'it',
    String? quality,
  }) async {
    if (kind == MediaKind.anime) return const [];
    final path = kind == MediaKind.movie
        ? '/torrent/movie/$rawId'
        : '/torrent/tv/$rawId/$season/$episode';

    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        'lang': language,
        if (quality != null && quality.isNotEmpty && quality != 'auto')
          'quality': quality,
      },
    );

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map(TorrentItem.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[VideoService] fetchTorrents error: $e');
    }
    return const [];
  }

  /// Fetch AnimeUnity episode list via `/anime/{id}/episodes`.
  static Future<AnimeEpisodesResponse?> fetchAnimeEpisodes(int animeId) async {
    final uri = Uri.parse('$_base/anime/$animeId/episodes');
    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return AnimeEpisodesResponse.fromJson(data);
      }
    } catch (e) {
      debugPrint('[VideoService] fetchAnimeEpisodes error: $e');
    }
    return null;
  }

  /// Fetch ready-to-run FFmpeg offload command (`?download=cmd`).
  static Future<DownloadCommandInfo?> fetchDownloadCommand({
    required MediaKind kind,
    required int id,
    int season = 1,
    int episode = 1,
    String language = 'it',
    String? quality,
  }) async {
    final path = switch (kind) {
      MediaKind.movie => '/movie/$id/',
      MediaKind.tv => '/tv/$id/$season/$episode/',
      MediaKind.anime => '/anime/$id/$episode/',
    };

    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        'download': 'cmd',
        'lang': language,
        if (quality != null && quality.isNotEmpty && quality != 'auto')
          'quality': quality,
      },
    );

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return DownloadCommandInfo.fromJson(data);
      }
    } catch (e) {
      debugPrint('[VideoService] fetchDownloadCommand error: $e');
    }
    return null;
  }

  /// Fetch movie navigation info: `/movie/{id}/?currentInfo=true`
  static Future<Video?> fetchMovieInfo({
    required int tmdbId,
    String language = 'it',
  }) async {
    final urlString = '$_base/movie/$tmdbId/?currentInfo=true&lang=$language';
    try {
      final response = await http
          .get(Uri.parse(urlString))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return Video.fromJson(data);
      }
    } catch (e) {
      debugPrint('[VideoService] fetchMovieInfo error: $e');
    }
    return null;
  }

  /// Fetches next episode metadata from endpoint:
  /// `GET /tv/{id}/{season}/{episode}/?nextepisode=true` or `/anime/{id}/{ep}/?nextepisode=true`
  static Future<Video?> fetchNextEpisode({
    required int tvId,
    required int season,
    required int episode,
    String language = 'it',
    bool isAnime = false,
  }) async {
    final urlString = isAnime
        ? '$_base/anime/$tvId/$episode/?nextepisode=true&lang=$language'
        : '$_base/tv/$tvId/$season/$episode/?nextepisode=true&lang=$language';
    debugPrint('[VideoService] Fetching next episode from API: $urlString');

    try {
      final response = await http
          .get(Uri.parse(urlString))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint(
          '[VideoService] API returned next episode data successfully',
        );
        return Video.fromJson(data);
      } else {
        debugPrint(
          '[VideoService] API request failed with status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[VideoService] Failed to fetch next episode via API: $e');
    }
    return null;
  }

  static Future<Video?> fetchCurrentEpisode({
    required int tvId,
    required int season,
    required int episode,
    String language = 'it',
    bool isAnime = false,
  }) async {
    final urlString = isAnime
        ? '$_base/anime/$tvId/$episode/?currentInfo=true&lang=$language'
        : '$_base/tv/$tvId/$season/$episode/?currentInfo=true&lang=$language';
    debugPrint('[VideoService] Fetching current episode from API: $urlString');

    try {
      final response = await http
          .get(Uri.parse(urlString))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return Video.fromJson(data);
      }
    } catch (e) {
      debugPrint('[VideoService] Failed to fetch current episode via API: $e');
    }
    return null;
  }
}
