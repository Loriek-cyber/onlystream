import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:onlystream/models/video_model.dart';
import 'package:onlystream/services/server_config_service.dart';
import 'package:onlystream/services/video_service.dart';
import 'package:onlystream/utils/constants.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  cancelled,
}

class DownloadTaskItem {
  final String taskId;
  final int mediaId;
  final String title;
  final String subtitle;
  final MediaKind mediaKind;
  final int? season;
  final int? episode;
  final String language;
  final String quality;
  final String? posterUrl;
  final String downloadUrl;
  String filePath;
  DownloadStatus status;
  int bytesReceived;
  String? errorMessage;
  final DateTime createdAt;

  DownloadTaskItem({
    required this.taskId,
    required this.mediaId,
    required this.title,
    required this.subtitle,
    required this.mediaKind,
    this.season,
    this.episode,
    required this.language,
    required this.quality,
    this.posterUrl,
    required this.downloadUrl,
    required this.filePath,
    this.status = DownloadStatus.queued,
    this.bytesReceived = 0,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get formattedBytes {
    if (bytesReceived <= 0) return '0 MB';
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;
    if (bytesReceived >= gb) {
      return '${(bytesReceived / gb).toStringAsFixed(2)} GB';
    }
    return '${(bytesReceived / mb).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'mediaId': mediaId,
        'title': title,
        'subtitle': subtitle,
        'mediaKind': mediaKind.value,
        'season': season,
        'episode': episode,
        'language': language,
        'quality': quality,
        'posterUrl': posterUrl,
        'downloadUrl': downloadUrl,
        'filePath': filePath,
        'status': status.name,
        'bytesReceived': bytesReceived,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadTaskItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'completed';
    final parsedStatus = DownloadStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => DownloadStatus.failed,
    );
    return DownloadTaskItem(
      taskId: json['taskId'] as String? ?? '',
      mediaId: (json['mediaId'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? 'Media',
      subtitle: json['subtitle'] as String? ?? '',
      mediaKind: MediaKind.fromString(json['mediaKind'] as String?),
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      language: json['language'] as String? ?? 'it',
      quality: json['quality'] as String? ?? '1080p',
      posterUrl: json['posterUrl'] as String?,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      status: parsedStatus == DownloadStatus.downloading
          ? DownloadStatus.failed
          : parsedStatus,
      bytesReceived: (json['bytesReceived'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Manages local library ("La Mia Lista"), watch history, and active/completed
/// MP4 downloads (single movies, TV episodes, entire seasons, or entire series).
class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();

  DownloadService._internal();

  final List<DownloadTaskItem> _tasks = [];
  final List<UnifiedSearchResult> _savedWatchlist = [];
  final List<Video> _watchHistory = [];
  final Map<String, http.Client> _activeClients = {};
  bool _isProcessingQueue = false;

  List<DownloadTaskItem> get tasks => List.unmodifiable(_tasks);
  List<UnifiedSearchResult> get savedWatchlist =>
      List.unmodifiable(_savedWatchlist);
  List<Video> get watchHistory => List.unmodifiable(_watchHistory);

  int get activeDownloadsCount => _tasks
      .where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued)
      .length;

  File get _storageFile {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final dir = Directory('$home/.onlystream');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return File('${dir.path}/downloads_and_library.json');
  }

  Future<void> init() async {
    try {
      final file = _storageFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        if (data['tasks'] is List) {
          _tasks
            ..clear()
            ..addAll(
              (data['tasks'] as List)
                  .whereType<Map<String, dynamic>>()
                  .map(DownloadTaskItem.fromJson),
            );
        }
        if (data['watchlist'] is List) {
          _savedWatchlist
            ..clear()
            ..addAll(
              (data['watchlist'] as List)
                  .whereType<Map<String, dynamic>>()
                  .map(UnifiedSearchResult.fromTmdbJson),
            );
        }
        if (data['history'] is List) {
          _watchHistory
            ..clear()
            ..addAll(
              (data['history'] as List)
                  .whereType<Map<String, dynamic>>()
                  .map(Video.fromJson),
            );
        }
      }
    } catch (e) {
      debugPrint('[DownloadService] Error loading storage: $e');
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final payload = {
        'tasks': _tasks.map((t) => t.toJson()).toList(),
        'watchlist': _savedWatchlist.map((w) => w.toJson()).toList(),
        'history': _watchHistory.map((h) => h.toJson()).toList(),
      };
      await _storageFile.writeAsString(json.encode(payload));
    } catch (e) {
      debugPrint('[DownloadService] Error persisting storage: $e');
    }
  }

  // ── Watchlist ("Salva nella Lista") ───────────────────────────────

  bool isSaved(int id, MediaKind kind) {
    return _savedWatchlist.any((w) => w.id == id && w.mediaKind == kind);
  }

  Future<bool> toggleSaved(UnifiedSearchResult item) async {
    final idx = _savedWatchlist.indexWhere(
        (w) => w.id == item.id && w.mediaKind == item.mediaKind);
    final bool added;
    if (idx >= 0) {
      _savedWatchlist.removeAt(idx);
      added = false;
    } else {
      _savedWatchlist.insert(0, item);
      added = true;
    }
    await _persist();
    notifyListeners();
    return added;
  }

  Future<void> addToHistory(Video video) async {
    _watchHistory.removeWhere((v) => v.id == video.id && v.type == video.type);
    _watchHistory.insert(0, video);
    if (_watchHistory.length > 25) {
      _watchHistory.removeLast();
    }
    await _persist();
    notifyListeners();
  }

  // ── Download Engine (Single Movie / Episode / Season / Full Series) ──

  String _sanitizeFilename(String input) {
    final clean = input
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return clean.isEmpty ? 'video' : clean;
  }

  String _buildDownloadUrl({
    required MediaKind kind,
    required int id,
    int? season,
    int? episode,
    required String language,
    required String quality,
  }) {
    final base = AppConstants.baseUrl;
    final qParam =
        (quality.isNotEmpty && quality != 'auto') ? '&quality=$quality' : '';
    switch (kind) {
      case MediaKind.movie:
        return '$base/movie/$id/?download=true&lang=$language$qParam';
      case MediaKind.tv:
        final s = season ?? 1;
        final e = episode ?? 1;
        return '$base/tv/$id/$s/$e/?download=true&lang=$language$qParam';
      case MediaKind.anime:
        final e = episode ?? 1;
        return '$base/anime/$id/$e/?download=true&lang=$language$qParam';
    }
  }

  /// Enqueue a single movie or single episode for MP4 download.
  Future<DownloadTaskItem> enqueueSingle({
    required int mediaId,
    required String title,
    required MediaKind mediaKind,
    int? season,
    int? episode,
    String? episodeTitle,
    String? language,
    String? quality,
    String? posterUrl,
  }) async {
    final lang = language ?? ServerConfigService.instance.defaultLanguage;
    final qual = quality ?? ServerConfigService.instance.preferredQuality;

    final String taskKey = switch (mediaKind) {
      MediaKind.movie => 'movie_${mediaId}_${lang}_$qual',
      MediaKind.tv => 'tv_${mediaId}_S${season ?? 1}E${episode ?? 1}_${lang}_$qual',
      MediaKind.anime => 'anime_${mediaId}_E${episode ?? 1}_${lang}_$qual',
    };

    final existingIdx = _tasks.indexWhere((t) => t.taskId == taskKey);
    if (existingIdx >= 0) {
      final existing = _tasks[existingIdx];
      if (existing.status == DownloadStatus.downloading ||
          existing.status == DownloadStatus.queued) {
        return existing;
      }
      _tasks.removeAt(existingIdx);
    }

    final subtitle = switch (mediaKind) {
      MediaKind.movie => 'Film • ${qual.toUpperCase()} • ${lang.toUpperCase()}',
      MediaKind.tv =>
        'S${(season ?? 1).toString().padLeft(2, '0')}E${(episode ?? 1).toString().padLeft(2, '0')}${episodeTitle != null ? " - $episodeTitle" : ""} • ${qual.toUpperCase()}',
      MediaKind.anime =>
        'Episodio ${episode ?? 1} • ${qual.toUpperCase()}',
    };

    final baseDir = ServerConfigService.instance.effectiveDownloadDir;
    final subFolder = mediaKind == MediaKind.movie
        ? baseDir
        : Directory('${baseDir.path}/${_sanitizeFilename(title)}');
    if (!subFolder.existsSync()) {
      try {
        subFolder.createSync(recursive: true);
      } catch (_) {}
    }

    final fileName = switch (mediaKind) {
      MediaKind.movie => '${_sanitizeFilename(title)}_${qual}_$lang.mp4',
      MediaKind.tv =>
        '${_sanitizeFilename(title)}_S${(season ?? 1).toString().padLeft(2, '0')}E${(episode ?? 1).toString().padLeft(2, '0')}_$qual.mp4',
      MediaKind.anime =>
        '${_sanitizeFilename(title)}_Ep${(episode ?? 1).toString().padLeft(2, '0')}_$qual.mp4',
    };

    final downloadUrl = _buildDownloadUrl(
      kind: mediaKind,
      id: mediaId,
      season: season,
      episode: episode,
      language: lang,
      quality: qual,
    );

    final item = DownloadTaskItem(
      taskId: taskKey,
      mediaId: mediaId,
      title: title,
      subtitle: subtitle,
      mediaKind: mediaKind,
      season: season,
      episode: episode,
      language: lang,
      quality: qual,
      posterUrl: posterUrl,
      downloadUrl: downloadUrl,
      filePath: '${subFolder.path}/$fileName',
    );

    _tasks.insert(0, item);
    await _persist();
    notifyListeners();
    unawaited(_processQueue());
    return item;
  }

  /// Batch download an entire season of a TV Series (or range of Anime episodes).
  Future<int> enqueueSeasonBatch({
    required int mediaId,
    required String title,
    required MediaKind mediaKind,
    required int seasonNumber,
    required int episodeCount,
    String? language,
    String? quality,
    String? posterUrl,
  }) async {
    int count = 0;
    final total = episodeCount.clamp(1, 200);
    for (int ep = 1; ep <= total; ep++) {
      await enqueueSingle(
        mediaId: mediaId,
        title: title,
        mediaKind: mediaKind,
        season: seasonNumber,
        episode: ep,
        language: language,
        quality: quality,
        posterUrl: posterUrl,
      );
      count++;
    }
    return count;
  }

  /// Batch download an entire TV Series across all seasons (or all episodes of an Anime).
  Future<int> enqueueFullSeries({
    required int mediaId,
    required String title,
    required MediaKind mediaKind,
    List<TvSeasonSummary>? knownSeasons,
    int? knownAnimeEpisodes,
    String? language,
    String? quality,
    String? posterUrl,
  }) async {
    final lang = language ?? ServerConfigService.instance.defaultLanguage;
    if (mediaKind == MediaKind.anime) {
      int totalEps = knownAnimeEpisodes ?? 0;
      if (totalEps <= 0) {
        final epResp = await VideoService.fetchAnimeEpisodes(mediaId);
        totalEps = epResp?.episodesCount ?? 12;
      }
      return enqueueSeasonBatch(
        mediaId: mediaId,
        title: title,
        mediaKind: MediaKind.anime,
        seasonNumber: 1,
        episodeCount: totalEps,
        language: lang,
        quality: quality,
        posterUrl: posterUrl,
      );
    }

    List<TvSeasonSummary> seasons = knownSeasons ?? [];
    if (seasons.isEmpty) {
      final dlData = await VideoService.fetchDownloadData(
        kind: MediaKind.tv,
        id: mediaId,
        season: 1,
        episode: 1,
        language: lang,
        includeTorrents: false,
      );
      seasons = dlData?.seasons ?? [];
    }

    if (seasons.isEmpty) {
      // Fallback: walk episodes via ?nextepisode=true or enqueue Season 1
      return enqueueSeasonBatch(
        mediaId: mediaId,
        title: title,
        mediaKind: MediaKind.tv,
        seasonNumber: 1,
        episodeCount: 10,
        language: lang,
        quality: quality,
        posterUrl: posterUrl,
      );
    }

    int totalQueued = 0;
    for (final s in seasons) {
      totalQueued += await enqueueSeasonBatch(
        mediaId: mediaId,
        title: title,
        mediaKind: MediaKind.tv,
        seasonNumber: s.seasonNumber,
        episodeCount: s.episodeCount,
        language: lang,
        quality: quality,
        posterUrl: posterUrl,
      );
    }
    return totalQueued;
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (true) {
        final nextIdx =
            _tasks.indexWhere((t) => t.status == DownloadStatus.queued);
        if (nextIdx == -1) break;
        final task = _tasks[nextIdx];
        await _executeDownload(task);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _executeDownload(DownloadTaskItem task) async {
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    notifyListeners();

    final client = http.Client();
    _activeClients[task.taskId] = client;
    IOSink? sink;

    try {
      final request = http.Request('GET', Uri.parse(task.downloadUrl));
      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Server ha risposto con stato HTTP ${streamedResponse.statusCode} (Assicurati che FFmpeg sia installato sul server API)',
        );
      }

      final outFile = File(task.filePath);
      if (!outFile.parent.existsSync()) {
        await outFile.parent.create(recursive: true);
      }
      sink = outFile.openWrite();

      int lastNotifiedBytes = 0;
      await for (final chunk in streamedResponse.stream) {
        if (task.status == DownloadStatus.cancelled) {
          throw Exception('Download annullato');
        }
        sink.add(chunk);
        task.bytesReceived += chunk.length;
        if (task.bytesReceived - lastNotifiedBytes >= 256 * 1024) {
          lastNotifiedBytes = task.bytesReceived;
          notifyListeners();
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (task.bytesReceived < 1024) {
        throw Exception('File MP4 ricevuto vuoto o incompleto');
      }

      task.status = DownloadStatus.completed;
    } catch (e) {
      await sink?.close();
      if (task.status != DownloadStatus.cancelled) {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      _activeClients.remove(task.taskId);
      client.close();
      await _persist();
      notifyListeners();
    }
  }

  Future<void> cancelTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.taskId == taskId);
    if (idx == -1) return;
    final task = _tasks[idx];
    task.status = DownloadStatus.cancelled;
    _activeClients[taskId]?.close();
    _activeClients.remove(taskId);
    await _persist();
    notifyListeners();
  }

  Future<void> retryTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.taskId == taskId);
    if (idx == -1) return;
    final task = _tasks[idx];
    task.status = DownloadStatus.queued;
    task.bytesReceived = 0;
    task.errorMessage = null;
    await _persist();
    notifyListeners();
    unawaited(_processQueue());
  }

  Future<void> removeTask(String taskId, {bool deleteFile = false}) async {
    await cancelTask(taskId);
    final idx = _tasks.indexWhere((t) => t.taskId == taskId);
    if (idx == -1) return;
    final task = _tasks.removeAt(idx);
    if (deleteFile && task.filePath.isNotEmpty) {
      try {
        final f = File(task.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearFinishedTasks() async {
    _tasks.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.failed ||
        t.status == DownloadStatus.cancelled);
    await _persist();
    notifyListeners();
  }
}
