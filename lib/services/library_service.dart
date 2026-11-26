import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onlystream/models/library.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:path_provider/path_provider.dart';

/// Manages the user's library (continue watching, saved, completed) with
/// server synchronization and offline JSON caching via `path_provider`.
class LibraryService extends ChangeNotifier {
  static final LibraryService instance = LibraryService();

  LibraryService({
    ApiClient? apiClient,
    ConfigService? configService,
    this._storageDirOverride,
    this.persist = true,
  })  : _apiClient = apiClient ?? ApiClient.instance,
        _config = configService ?? ConfigService.instance;

  final ApiClient _apiClient;
  final ConfigService _config;
  final Directory? _storageDirOverride;
  final bool persist;

  LibrarySnapshot _snapshot = LibrarySnapshot.empty;
  bool _isSyncing = false;
  bool _isOffline = false;
  String? _lastError;
  Directory? _resolvedDir;

  LibrarySnapshot get snapshot => _snapshot;
  List<LibraryItemView> get continueWatching => _snapshot.continueWatching;
  List<LibraryItemView> get saved => _snapshot.saved;
  List<LibraryItemView> get completed => _snapshot.completed;
  List<LibraryItemView> get items => _snapshot.items;
  List<LibraryItemView> get newEpisodesItems =>
      _snapshot.items.where((item) => item.hasNewEpisodes).toList();
  bool get isSyncing => _isSyncing;
  bool get isOffline => _isOffline;
  String? get lastError => _lastError;

  Future<Directory> _resolveDir() async {
    if (_storageDirOverride != null) {
      if (!await _storageDirOverride.exists()) {
        await _storageDirOverride.create(recursive: true);
      }
      return _storageDirOverride;
    }
    if (_resolvedDir != null) return _resolvedDir!;
    try {
      final dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _resolvedDir = dir;
      return dir;
    } catch (_) {
      final fallback = Directory.systemTemp;
      _resolvedDir = fallback;
      return fallback;
    }
  }

  Future<File> _cacheFile() async {
    final dir = await _resolveDir();
    return File('${dir.path}/library_cache.json');
  }

  Future<void> init({bool syncOnInit = true}) async {
    await _loadCache();
    notifyListeners();
    if (syncOnInit) {
      unawaited(refresh());
    }
  }

  Future<void> _loadCache() async {
    if (!persist) return;
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content);
        if (decoded is Map<String, dynamic>) {
          _snapshot = LibrarySnapshot.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('[LibraryService] Failed to load cache: $e');
    }
  }

  Future<void> _saveCache() async {
    if (!persist) return;
    try {
      final file = await _cacheFile();
      await file.writeAsString(json.encode(_snapshot.toJson()));
    } catch (e) {
      debugPrint('[LibraryService] Failed to save cache: $e');
    }
  }

  LibraryItemView _mergeEpisodePositions(
    LibraryItemView incoming,
    LibraryItemView? existing,
  ) {
    if (existing == null || existing.episodePositions.isEmpty) {
      return incoming;
    }
    final merged = Map<String, EpisodeProgress>.from(existing.episodePositions)
      ..addAll(incoming.episodePositions);
    return incoming.copyWith(episodePositions: merged);
  }

  Future<void> refresh({String? lang}) async {
    _isSyncing = true;
    notifyListeners();

    try {
      final fetched = await _apiClient.getLibrary(
        lang: lang ?? _config.language,
      );
      final existingByKey = <String, LibraryItemView>{
        for (final item in _snapshot.items) item.key: item,
      };
      final mergedItems = fetched.items
          .map((item) => _mergeEpisodePositions(item, existingByKey[item.key]))
          .toList();
      _snapshot = LibrarySnapshot(
        continueWatching: fetched.continueWatching
            .map(
              (item) => _mergeEpisodePositions(item, existingByKey[item.key]),
            )
            .toList(),
        saved: fetched.saved
            .map(
              (item) => _mergeEpisodePositions(item, existingByKey[item.key]),
            )
            .toList(),
        completed: fetched.completed
            .map(
              (item) => _mergeEpisodePositions(item, existingByKey[item.key]),
            )
            .toList(),
        items: mergedItems,
      );
      _isOffline = false;
      _lastError = null;
      await _saveCache();
    } catch (e) {
      _isOffline = true;
      _lastError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  LibraryItemView? entryFor(MediaKind kind, int id) {
    final targetKey = '${kind.wireValue}:$id';
    for (final item in _snapshot.items) {
      if (item.key == targetKey) return item;
    }
    for (final item in _snapshot.continueWatching) {
      if (item.key == targetKey) return item;
    }
    for (final item in _snapshot.saved) {
      if (item.key == targetKey) return item;
    }
    for (final item in _snapshot.completed) {
      if (item.key == targetKey) return item;
    }
    return null;
  }

  bool isTracked(MediaKind kind, int id) => entryFor(kind, id) != null;

  bool isEpisodeWatched(MediaKind kind, int id, int season, int episode) {
    final entry = entryFor(kind, id);
    if (entry == null) return false;
    return entry.isEpisodeWatched(season, episode);
  }

  EpisodeProgress? episodeProgress(
    MediaKind kind,
    int id,
    int season,
    int episode,
  ) {
    final entry = entryFor(kind, id);
    if (entry == null) return null;
    return entry.progressForEpisode(season, episode);
  }

  int episodePositionSecs(MediaKind kind, int id, int season, int episode) {
    return episodeProgress(kind, id, season, episode)?.positionSecs ?? 0;
  }

  void _applyLocalEntry(LibraryItemView updated) {
    final list = _snapshot.items.where((e) => e.key != updated.key).toList()
      ..insert(0, updated);
    _snapshot = LibrarySnapshot.fromItems(list);
    notifyListeners();
    unawaited(_saveCache());
  }

  void _removeLocalEntry(MediaKind kind, int id) {
    final key = '${kind.wireValue}:$id';
    final list = _snapshot.items.where((e) => e.key != key).toList();
    _snapshot = LibrarySnapshot.fromItems(list);
    notifyListeners();
    unawaited(_saveCache());
  }

  /// Toggles saved status for a title: removes it if already tracked as saved,
  /// or saves it when absent.
  Future<void> toggleSaved({
    required MediaKind kind,
    required int id,
    required bool isAnime,
    required String title,
    String? poster,
    String? backdrop,
    String? year,
  }) async {
    final existing = entryFor(kind, id);
    if (existing != null) {
      await remove(kind, id);
      return;
    }
    await setStatus(
      kind: kind,
      id: id,
      isAnime: isAnime,
      title: title,
      poster: poster,
      backdrop: backdrop,
      year: year,
      status: WatchStatus.saved,
      preferredLang: _config.language,
    );
  }

  Future<void> setStatus({
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
    final existing = entryFor(kind, id);
    final optimistic = LibraryItemView(
      id: id,
      kind: kind,
      isAnime: isAnime,
      title: title,
      poster: poster ?? existing?.poster,
      backdrop: backdrop ?? existing?.backdrop,
      year: year ?? existing?.year,
      status: status,
      currentSeason: currentSeason ?? existing?.currentSeason,
      currentEpisode: currentEpisode ?? existing?.currentEpisode,
      positionSecs: existing?.positionSecs ?? 0,
      durationSecs: existing?.durationSecs ?? 0,
      watchedEpisodes: existing?.watchedEpisodes ?? const [],
      episodePositions: existing?.episodePositions ?? const {},
      preferredLang: preferredLang ?? existing?.preferredLang ?? _config.language,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      nextEpisode: existing?.nextEpisode,
      hasNewEpisodes: existing?.hasNewEpisodes ?? false,
      newEpisodesCount: existing?.newEpisodesCount ?? 0,
      latestAiredSeason: existing?.latestAiredSeason,
      latestAiredEpisode: existing?.latestAiredEpisode,
    );
    _applyLocalEntry(optimistic);

    try {
      final serverItem = await _apiClient.upsertLibrary(
        kind: kind,
        id: id,
        isAnime: isAnime,
        title: title,
        poster: poster,
        backdrop: backdrop,
        year: year,
        status: status,
        currentSeason: currentSeason,
        currentEpisode: currentEpisode,
        preferredLang: preferredLang ?? _config.language,
      );
      _isOffline = false;
      _applyLocalEntry(_mergeEpisodePositions(serverItem, optimistic));
    } catch (e) {
      _isOffline = true;
      _lastError = e.toString();
    }
  }

  Future<void> reportProgress({
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
  }) async {
    final existing = entryFor(kind, id);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final nearEnd =
        durationSecs > 0 && (positionSecs / durationSecs) >= 0.92;
    final nextStatus = (kind == MediaKind.movie && nearEnd)
        ? WatchStatus.completed
        : WatchStatus.watching;

    final updatedPositions = Map<String, EpisodeProgress>.from(
      existing?.episodePositions ?? const {},
    );
    if (kind == MediaKind.tv && season != null && episode != null) {
      updatedPositions[LibraryItemView.episodeKey(season, episode)] =
          EpisodeProgress(
        positionSecs: positionSecs,
        durationSecs: durationSecs,
        updatedAt: nowIso,
      );
    }

    final optimistic = LibraryItemView(
      id: id,
      kind: kind,
      isAnime: isAnime,
      title: title,
      poster: poster ?? existing?.poster,
      backdrop: backdrop ?? existing?.backdrop,
      year: year ?? existing?.year,
      status: nextStatus,
      currentSeason: season ?? existing?.currentSeason,
      currentEpisode: episode ?? existing?.currentEpisode,
      positionSecs: positionSecs,
      durationSecs: durationSecs,
      watchedEpisodes: existing?.watchedEpisodes ?? const [],
      episodePositions: updatedPositions,
      preferredLang: preferredLang ?? existing?.preferredLang ?? _config.language,
      updatedAt: nowIso,
      nextEpisode: existing?.nextEpisode,
      hasNewEpisodes: existing?.hasNewEpisodes ?? false,
      newEpisodesCount: existing?.newEpisodesCount ?? 0,
      latestAiredSeason: existing?.latestAiredSeason,
      latestAiredEpisode: existing?.latestAiredEpisode,
    );
    _applyLocalEntry(optimistic);

    try {
      final serverItem = await _apiClient.reportProgress(
        kind: kind,
        id: id,
        isAnime: isAnime,
        title: title,
        poster: poster,
        backdrop: backdrop,
        year: year,
        season: season,
        episode: episode,
        positionSecs: positionSecs,
        durationSecs: durationSecs,
        preferredLang: preferredLang ?? _config.language,
        lang: _config.language,
      );
      _isOffline = false;
      _applyLocalEntry(_mergeEpisodePositions(serverItem, optimistic));
    } catch (e) {
      _isOffline = true;
      _lastError = e.toString();
    }
  }

  Future<void> toggleEpisodeWatched({
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
  }) async {
    final existing = entryFor(kind, id);
    final code =
        'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
    final currentWatched =
        List<String>.from(existing?.watchedEpisodes ?? const []);
    final normalizedCode = code.toLowerCase();
    currentWatched.removeWhere((e) =>
        e.trim().toLowerCase() == normalizedCode ||
        e.trim().toLowerCase() == '$season:$episode' ||
        e.trim().toLowerCase() ==
            's${season.toString().padLeft(2, '0')}e${episode.toString().padLeft(2, '0')}');
    if (watched) {
      currentWatched.add(code);
    }

    final optimistic = LibraryItemView(
      id: id,
      kind: kind,
      isAnime: isAnime,
      title: title,
      poster: poster ?? existing?.poster,
      backdrop: backdrop ?? existing?.backdrop,
      year: year ?? existing?.year,
      status: existing?.status ?? WatchStatus.watching,
      currentSeason: existing?.currentSeason ?? season,
      currentEpisode: existing?.currentEpisode ?? episode,
      positionSecs: existing?.positionSecs ?? 0,
      durationSecs: existing?.durationSecs ?? 0,
      watchedEpisodes: currentWatched,
      episodePositions: existing?.episodePositions ?? const {},
      preferredLang: existing?.preferredLang ?? _config.language,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      nextEpisode: existing?.nextEpisode,
      hasNewEpisodes: existing?.hasNewEpisodes ?? false,
      newEpisodesCount: existing?.newEpisodesCount ?? 0,
      latestAiredSeason: existing?.latestAiredSeason,
      latestAiredEpisode: existing?.latestAiredEpisode,
    );
    _applyLocalEntry(optimistic);

    try {
      final serverItem = await _apiClient.toggleWatched(
        kind: kind,
        id: id,
        season: season,
        episode: episode,
        watched: watched,
        isAnime: isAnime,
        title: title,
        poster: poster,
        backdrop: backdrop,
        year: year,
        lang: _config.language,
      );
      _isOffline = false;
      _applyLocalEntry(_mergeEpisodePositions(serverItem, optimistic));
    } catch (e) {
      _isOffline = true;
      _lastError = e.toString();
    }
  }

  Future<void> remove(MediaKind kind, int id) async {
    _removeLocalEntry(kind, id);
    try {
      await _apiClient.deleteLibraryItem(kind, id);
      _isOffline = false;
    } catch (e) {
      _isOffline = true;
      _lastError = e.toString();
    }
  }

  /// Syncs a `MediaDetail.library` view back into the cached snapshot when
  /// opening a title detail page.
  void mergeServerItem(LibraryItemView? item) {
    if (item == null) return;
    final existing = entryFor(item.kind, item.id);
    _applyLocalEntry(_mergeEpisodePositions(item, existing));
  }
}
