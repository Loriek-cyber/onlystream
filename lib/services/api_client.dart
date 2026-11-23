import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:onlystream/models/library.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/services/config_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Typed HTTP client for EasyStream API v1.0.0.
class ApiClient {
  ApiClient({
    this._config,
    this._baseUrlProvider,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  static final ApiClient instance = ApiClient(config: ConfigService.instance);

  final ConfigService? _config;
  final String Function()? _baseUrlProvider;
  final http.Client _client;

  static const Duration _defaultTimeout = Duration(seconds: 12);
  static const Duration _resolveTimeout = Duration(seconds: 25);

  String get baseUrl {
    if (_baseUrlProvider != null) {
      return ConfigService.normalizeUrl(_baseUrlProvider());
    }
    return (_config ?? ConfigService.instance).baseUrl;
  }

  /// Resolves either an absolute URL or a server-relative path like
  /// `/stream/torrent/...` against the active EasyStream server `baseUrl`.
  String resolveStreamUrl(String urlOrPath) {
    final trimmed = urlOrPath.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$baseUrl$trimmed';
    }
    return '$baseUrl/$trimmed';
  }

  Uri _uri(String path, [Map<String, String?>? query]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse('$baseUrl$cleanPath');
    if (query == null) return base;
    final filtered = <String, String>{};
    for (final entry in query.entries) {
      final value = entry.value;
      if (value != null && value.isNotEmpty) {
        filtered[entry.key] = value;
      }
    }
    if (filtered.isEmpty) return base;
    return base.replace(queryParameters: filtered);
  }

  Future<dynamic> _getJson(
    Uri uri, {
    Duration timeout = _defaultTimeout,
  }) async {
    final response = await _client.get(uri).timeout(timeout);
    return _decodeResponse(response);
  }

  Future<dynamic> _sendJson(
    String method,
    Uri uri,
    Map<String, dynamic> body, {
    Duration timeout = _defaultTimeout,
  }) async {
    final headers = const {'Content-Type': 'application/json'};
    final encoded = json.encode(body);
    final http.Response response;
    if (method == 'PUT') {
      response = await _client
          .put(uri, headers: headers, body: encoded)
          .timeout(timeout);
    } else {
      response = await _client
          .post(uri, headers: headers, body: encoded)
          .timeout(timeout);
    }
    return _decodeResponse(response);
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'HTTP ${response.statusCode}';
      if (response.body.isNotEmpty) {
        try {
          final parsed = json.decode(response.body);
          if (parsed is Map<String, dynamic>) {
            message = parsed['error']?.toString() ??
                parsed['message']?.toString() ??
                message;
          }
        } catch (_) {
          message = response.body;
        }
      }
      throw ApiException(response.statusCode, message);
    }
    if (response.body.isEmpty) return null;
    return json.decode(response.body);
  }

  Future<HealthStatus> checkHealth() async {
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 4));
      sw.stop();
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return HealthStatus.fromJson(data, latencyMs: sw.elapsedMilliseconds);
      }
      return HealthStatus(
        isOnline: false,
        latencyMs: sw.elapsedMilliseconds,
        error: 'HTTP ${response.statusCode}',
      );
    } catch (e) {
      sw.stop();
      return HealthStatus(
        isOnline: false,
        latencyMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  Future<List<MediaSummary>> search(
    String query, {
    String type = 'all',
    String lang = 'it',
  }) async {
    final decoded = await _getJson(
      _uri('/search', {'q': query, 'type': type, 'lang': lang}),
    );
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MediaSummary.fromJson)
        .toList();
  }

  Future<List<MediaSummary>> discover({
    required String category,
    String genre = '',
    String lang = 'it',
    int page = 1,
  }) async {
    final decoded = await _getJson(
      _uri('/discover', {
        'category': category,
        'genre': genre,
        'lang': lang,
        'page': '$page',
      }),
    );
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MediaSummary.fromJson)
        .toList();
  }

  Future<List<GenreOption>> getGenres() async {
    final decoded = await _getJson(_uri('/genres'));
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GenreOption.fromJson)
        .toList();
  }

  Future<MediaDetail> getMediaDetail(
    MediaKind kind,
    int id, {
    String lang = 'it',
  }) async {
    final decoded = await _getJson(
      _uri('/media/${kind.wireValue}/$id', {'lang': lang}),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(500, 'Risposta media non valida');
    }
    return MediaDetail.fromJson(decoded);
  }

  Future<SeasonDetail> getSeasonDetail(
    int tvId,
    int season, {
    String lang = 'it',
  }) async {
    final decoded = await _getJson(
      _uri('/media/tv/$tvId/season/$season', {'lang': lang}),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(500, 'Risposta stagione non valida');
    }
    return SeasonDetail.fromJson(decoded);
  }

  Future<ResolvedStream> resolveStream({
    required MediaKind kind,
    required int id,
    int season = 1,
    int episode = 1,
    String lang = 'it',
    String quality = 'auto',
    String source = 'auto',
  }) async {
    final decoded = await _getJson(
      _uri('/stream/resolve/${kind.wireValue}/$id', {
        'season': '$season',
        'episode': '$episode',
        'lang': lang,
        'quality': quality,
        'source': source,
      }),
      timeout: _resolveTimeout,
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(500, 'Risposta stream non valida');
    }
    return ResolvedStream.fromJson(decoded);
  }

  String buildHlsStreamUrl({
    required MediaKind kind,
    required int id,
    int season = 1,
    int episode = 1,
    String lang = 'it',
    String quality = 'auto',
  }) {
    return _uri('/stream/hls/${kind.wireValue}/$id', {
      'season': '$season',
      'episode': '$episode',
      'lang': lang,
      'quality': quality,
    }).toString();
  }

  String buildTorrentStreamUrl({
    required String infoHash,
    int? fileIdx,
    int? season,
    int? episode,
  }) {
    return _uri('/stream/torrent/$infoHash', {
      if (fileIdx != null) 'file_idx': '$fileIdx',
      if (season != null) 'season': '$season',
      if (episode != null) 'episode': '$episode',
    }).toString();
  }

  Future<bool> stopTorrent(String infoHash) async {
    final cleanHash = infoHash.trim();
    if (cleanHash.isEmpty) return true;
    try {
      final response = await _client
          .delete(_uri('/torrents/$cleanHash'))
          .timeout(const Duration(seconds: 6));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopAllTorrents() async {
    try {
      final response = await _client
          .delete(_uri('/torrents'))
          .timeout(const Duration(seconds: 6));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<LibrarySnapshot> getLibrary({String lang = 'it'}) async {
    final decoded = await _getJson(_uri('/library', {'lang': lang}));
    if (decoded is! Map<String, dynamic>) {
      return LibrarySnapshot.empty;
    }
    return LibrarySnapshot.fromJson(decoded);
  }

  Future<List<LibraryItemView>> getLibraryUpdates({String lang = 'it'}) async {
    final decoded = await _getJson(_uri('/library/updates', {'lang': lang}));
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(LibraryItemView.fromJson)
        .toList();
  }

  Future<LibraryItemView> upsertLibrary({
    required MediaKind kind,
    required int id,
    required bool isAnime,
    required String title,
    String? poster,
    String? backdrop,
    String? year,
    required WatchStatus status,
    int? currentSeason,
    int? currentEpisode,
    String? preferredLang,
  }) async {
    final decoded = await _sendJson(
      'PUT',
      _uri('/library/${kind.wireValue}/$id'),
      {
        'is_anime': isAnime,
        'title': title,
        'poster': ?poster,
        'backdrop': ?backdrop,
        'year': ?year,
        'status': status.wireValue,
        'current_season': ?currentSeason,
        'current_episode': ?currentEpisode,
        'preferred_lang': ?preferredLang,
      },
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(500, 'Risposta libreria non valida');
    }
    return LibraryItemView.fromJson(decoded);
  }

  Future<bool> deleteLibraryItem(MediaKind kind, int id) async {
    final response = await _client
        .delete(_uri('/library/${kind.wireValue}/$id'))
        .timeout(_defaultTimeout);
    final decoded = _decodeResponse(response);
    if (decoded is Map<String, dynamic>) {
      return decoded['deleted'] as bool? ?? true;
    }
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<LibraryItemView> reportProgress({
    required MediaKind kind,
    required int id,
    required bool isAnime,
    required String title,
    String? poster,
    String? backdrop,
    String? year,
    int? season,
    int? episode,
    required int positionSecs,
    required int durationSecs,
    String? preferredLang,
    String lang = 'it',
  }) async {
    final decoded = await _sendJson(
      'POST',
      _uri('/library/${kind.wireValue}/$id/progress', {'lang': lang}),
      {
        'is_anime': isAnime,
        'title': title,
        'poster': ?poster,
        'backdrop': ?backdrop,
        'year': ?year,
        'season': ?season,
        'episode': ?episode,
        'position_secs': positionSecs,
        'duration_secs': durationSecs,
        'preferred_lang': ?preferredLang,
      },
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(500, 'Risposta progresso non valida');
    }
    return LibraryItemView.fromJson(decoded);
  }

  Future<LibraryItemView> toggleWatched({
    required MediaKind kind,
    required int id,
    required int season,
    required int episode,
    required bool watched,
    required bool isAnime,
    required String title,
    String? poster,
    String? backdrop,
    String? year,
    String lang = 'it',
  }) async {
    final decoded = await _sendJson(
      'POST',
      _uri('/library/${kind.wireValue}/$id/watched', {'lang': lang}),
      {
        'season': season,
        'episode': episode,
        'watched': watched,
        'is_anime': isAnime,
        'title': title,
        'poster': ?poster,
        'backdrop': ?backdrop,
        'year': ?year,
      },
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(500, 'Risposta watched non valida');
    }
    return LibraryItemView.fromJson(decoded);
  }
}
