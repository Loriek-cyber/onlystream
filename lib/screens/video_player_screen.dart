import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';

class VideoPlayerScreen extends StatefulWidget {
  final MediaSummary media;
  final int season;
  final int episode;
  final String? episodeTitle;
  final String? initialLanguage;
  final String? initialQuality;
  final String? initialSource;
  final TorrentSource? initialTorrent;
  final int initialPositionSecs;

  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;

  const VideoPlayerScreen({
    super.key,
    required this.media,
    this.season = 1,
    this.episode = 1,
    this.episodeTitle,
    this.initialLanguage,
    this.initialQuality,
    this.initialSource,
    this.initialTorrent,
    this.initialPositionSecs = 0,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late final ApiClient _apiClient;
  late final ConfigService _config;
  late final LibraryService _library;
  late final TorrentSessionGuard _torrentGuard;
  late final PlayerAdapter _player;

  late int _season;
  late int _episode;
  String? _episodeTitle;

  late String _selectedLanguage;
  late String _selectedQuality;
  late String _selectedSource;
  TorrentSource? _selectedTorrent;

  ResolvedStream? _resolved;
  bool _isResolving = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  String? _errorMessage;
  String _activeMode = 'hls';

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _pendingResumePosition = Duration.zero;

  List<PlayerTrackItem> _playerAudioTracks = [];
  List<PlayerTrackItem> _playerSubtitleTracks = [];
  String? _activeAudioId;
  String? _activeSubtitleId;

  int _resolveEpoch = 0;
  bool _advancingEpisode = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  Timer? _hideControlsTimer;
  Timer? _progressTimer;
  Timer? _pausedTorrentStopTimer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;
    _torrentGuard =
        widget.torrentGuard ?? TorrentSessionGuard(apiClient: _apiClient);
    _player = (widget.playerFactory ?? MediaKitPlayerAdapter.new)();

    _season = widget.season;
    _episode = widget.episode;
    _episodeTitle = widget.episodeTitle;

    _selectedLanguage = widget.initialLanguage ?? _config.language;
    _selectedQuality = widget.initialQuality ?? _config.quality;
    _selectedSource = widget.initialSource ??
        (widget.initialTorrent != null ? 'torrent' : _config.source);
    _selectedTorrent = widget.initialTorrent;

    if (widget.initialPositionSecs > 0) {
      _pendingResumePosition = Duration(seconds: widget.initialPositionSecs);
    }

    _setupPlayerListeners();
    _startProgressTimer();
    _startHideControlsTimer();
    unawaited(_loadAndPlay());
  }

  void _setupPlayerListeners() {
    _subscriptions.addAll([
      _player.playingStream.listen((playing) {
        if (!mounted) return;
        setState(() => _isPlaying = playing);
        if (playing) {
          _pausedTorrentStopTimer?.cancel();
          _startHideControlsTimer();
        }
      }),
      _player.bufferingStream.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
      _player.positionStream.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
      _player.durationStream.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      _player.completedStream.listen((completed) {
        if (completed) {
          unawaited(_handlePlaybackCompleted());
        }
      }),
      _player.audioTracksStream.listen((tracks) {
        if (mounted) setState(() => _playerAudioTracks = tracks);
      }),
      _player.subtitleTracksStream.listen((tracks) {
        if (mounted) setState(() => _playerSubtitleTracks = tracks);
      }),
      _player.activeAudioIdStream.listen((id) {
        if (mounted) setState(() => _activeAudioId = id);
      }),
      _player.activeSubtitleIdStream.listen((id) {
        if (mounted) setState(() => _activeSubtitleId = id);
      }),
      _player.errorStream.listen((error) {
        if (error.trim().isEmpty) return;
        if (mounted) {
          setState(() => _errorMessage = error);
        }
      }),
    ]);
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
  }

  Future<void> _saveProgress({bool force = false}) async {
    final posSecs = _position.inSeconds;
    final durSecs = _duration.inSeconds;
    if (!force && (durSecs <= 0 || posSecs <= 0)) return;
    if (durSecs <= 0 && posSecs <= 0) return;

    await _library.reportProgress(
      kind: widget.media.kind,
      id: widget.media.id,
      isAnime: widget.media.isAnime,
      title: widget.media.title,
      poster: widget.media.poster,
      backdrop: widget.media.backdrop,
      year: widget.media.year,
      season: widget.media.kind == MediaKind.tv ? _season : null,
      episode: widget.media.kind == MediaKind.tv ? _episode : null,
      positionSecs: posSecs,
      durationSecs: durSecs,
      preferredLang: _selectedLanguage,
    );
  }

  Future<void> _handlePlaybackCompleted() async {
    await _saveProgress(force: true);
    if (widget.media.kind == MediaKind.tv) {
      await _library.toggleEpisodeWatched(
        kind: widget.media.kind,
        id: widget.media.id,
        season: _season,
        episode: _episode,
        watched: true,
        isAnime: widget.media.isAnime,
        title: widget.media.title,
        poster: widget.media.poster,
        backdrop: widget.media.backdrop,
        year: widget.media.year,
      );
      await _playNextEpisode();
    } else {
      await _torrentGuard.stopActive();
    }
  }

  Future<void> _loadAndPlay({TorrentSource? explicitTorrent}) async {
    final epoch = ++_resolveEpoch;

    if (mounted) {
      setState(() {
        _isResolving = true;
        _errorMessage = null;
      });
    }

    await _torrentGuard.stopActive();
    if (!mounted || epoch != _resolveEpoch) return;

    final startAt = _pendingResumePosition;
    _pendingResumePosition = Duration.zero;

    if (explicitTorrent != null) {
      _selectedTorrent = explicitTorrent;
      _selectedSource = 'torrent';
      _activeMode = 'torrent';
      await _torrentGuard.activateTorrent(explicitTorrent.infoHash);
      if (!mounted || epoch != _resolveEpoch) return;

      final streamPath = explicitTorrent.streamUrl.isNotEmpty
          ? explicitTorrent.streamUrl
          : _apiClient.buildTorrentStreamUrl(
              infoHash: explicitTorrent.infoHash,
              fileIdx: explicitTorrent.fileIdx,
              season: widget.media.kind == MediaKind.tv ? _season : null,
              episode: widget.media.kind == MediaKind.tv ? _episode : null,
            );
      final streamUrl = _apiClient.resolveStreamUrl(streamPath);
      await _player.open(streamUrl, start: startAt);
      if (mounted && epoch == _resolveEpoch) {
        setState(() => _isResolving = false);
      }
      return;
    }

    try {
      final resolved = await _apiClient.resolveStream(
        kind: widget.media.kind,
        id: widget.media.id,
        season: _season,
        episode: _episode,
        lang: _selectedLanguage,
        quality: _selectedQuality,
        source: _selectedSource,
      );
      if (!mounted || epoch != _resolveEpoch) return;

      _resolved = resolved;

      final shouldUseTorrent = resolved.recommendedMode == 'torrent' &&
          (resolved.recommendedInfoHash?.isNotEmpty == true ||
              resolved.torrents.isNotEmpty);

      if (shouldUseTorrent) {
        final hash = resolved.recommendedInfoHash ??
            resolved.torrents.first.infoHash;
        _activeMode = 'torrent';
        await _torrentGuard.activateTorrent(hash);
        if (!mounted || epoch != _resolveEpoch) return;

        final rawUrl = resolved.recommendedUrl.isNotEmpty
            ? resolved.recommendedUrl
            : resolved.torrents.first.streamUrl;
        final fullUrl = _apiClient.resolveStreamUrl(rawUrl);
        await _player.open(fullUrl, start: startAt);
      } else {
        _activeMode = 'hls';
        await _torrentGuard.switchToHls();
        if (!mounted || epoch != _resolveEpoch) return;

        final rawUrl = resolved.recommendedUrl.isNotEmpty
            ? resolved.recommendedUrl
            : (resolved.hls?.playlistUrl ??
                _apiClient.buildHlsStreamUrl(
                  kind: widget.media.kind,
                  id: widget.media.id,
                  season: _season,
                  episode: _episode,
                  lang: _selectedLanguage,
                  quality: _selectedQuality,
                ));
        final fullUrl = _apiClient.resolveStreamUrl(rawUrl);
        final referer = resolved.hls?.referer?.trim();
        final headers = (referer != null && referer.isNotEmpty)
            ? {'Referer': referer}
            : null;
        await _player.open(fullUrl, httpHeaders: headers, start: startAt);
      }

      if (mounted && epoch == _resolveEpoch) {
        setState(() => _isResolving = false);
      }
    } catch (e) {
      if (!mounted || epoch != _resolveEpoch) return;
      setState(() {
        _isResolving = false;
        _errorMessage = 'Impossibile avviare la riproduzione: $e';
      });
    }
  }

  Future<void> _reloadWithCurrentOptions({bool preservePosition = true}) async {
    if (preservePosition && _position > Duration.zero) {
      _pendingResumePosition = _position;
    }
    _selectedTorrent = null;
    await _loadAndPlay();
  }

  Future<void> _playNextEpisode() async {
    if (_advancingEpisode) return;
    _advancingEpisode = true;
    try {
      await _saveProgress(force: true);
      await _torrentGuard.stopActive();

      final next = _resolved?.nextEpisode;
      if (mounted) {
        setState(() {
          _season = next?.season ?? _season;
          _episode = next?.episode ?? (_episode + 1);
          _episodeTitle = next?.name;
          _position = Duration.zero;
          _duration = Duration.zero;
          _selectedTorrent = null;
          _playerAudioTracks = [];
          _playerSubtitleTracks = [];
        });
      }
      _pendingResumePosition = Duration.zero;
      await _loadAndPlay();
    } finally {
      _advancingEpisode = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.detached) {
      unawaited(_saveProgress(force: true));
      unawaited(_torrentGuard.stopActive());
    } else if (state == AppLifecycleState.paused) {
      unawaited(_saveProgress(force: true));
      _pausedTorrentStopTimer?.cancel();
      _pausedTorrentStopTimer = Timer(const Duration(seconds: 15), () {
        if (mounted &&
            _lifecycleState == AppLifecycleState.paused &&
            !_isPlaying) {
          unawaited(_torrentGuard.stopActive());
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      _pausedTorrentStopTimer?.cancel();
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _pausedTorrentStopTimer?.cancel();
    unawaited(_saveProgress(force: true));
    unawaited(_torrentGuard.stopActive());
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    unawaited(_player.dispose());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _showOptionsDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Opzioni stream',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Lingua',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: const [
                    ('it', 'Italiano'),
                    ('en', 'English'),
                  ].map((opt) {
                    return ChoiceChip(
                      label: Text(opt.$2),
                      selected: _selectedLanguage == opt.$1,
                      onSelected: (_) {
                        Navigator.pop(ctx);
                        if (_selectedLanguage != opt.$1) {
                          setState(() => _selectedLanguage = opt.$1);
                          unawaited(_reloadWithCurrentOptions());
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Qualità',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    ('auto', 'Auto'),
                    ('2160p', '2160p'),
                    ('1080p', '1080p'),
                    ('720p', '720p'),
                  ].map((opt) {
                    return ChoiceChip(
                      label: Text(opt.$2),
                      selected: _selectedQuality == opt.$1,
                      onSelected: (_) {
                        Navigator.pop(ctx);
                        if (_selectedQuality != opt.$1) {
                          setState(() => _selectedQuality = opt.$1);
                          unawaited(_reloadWithCurrentOptions());
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sorgente',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: const [
                    ('auto', 'Auto'),
                    ('hls', 'HLS'),
                    ('torrent', 'Torrent'),
                  ].map((opt) {
                    return ChoiceChip(
                      label: Text(opt.$2),
                      selected: _selectedSource == opt.$1,
                      onSelected: (_) {
                        Navigator.pop(ctx);
                        if (_selectedSource != opt.$1) {
                          setState(() => _selectedSource = opt.$1);
                          unawaited(_reloadWithCurrentOptions());
                        }
                      },
                    );
                  }).toList(),
                ),
                if (_resolved != null && _resolved!.torrents.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Torrent disponibili',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._resolved!.torrents.take(6).map((t) {
                    final active = _selectedTorrent?.infoHash == t.infoHash ||
                        (_activeMode == 'torrent' &&
                            _torrentGuard.activeInfoHash ==
                                t.infoHash.toLowerCase());
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        [
                          t.quality.toUpperCase(),
                          '${t.seeders} seed',
                          if (t.formattedSize.isNotEmpty) t.formattedSize,
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      trailing: active
                          ? const Icon(
                              Icons.check,
                              color: AppColors.textPrimary,
                              size: 18,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (_position > Duration.zero) {
                          _pendingResumePosition = _position;
                        }
                        unawaited(_loadAndPlay(explicitTorrent: t));
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAudioTracksDialog() async {
    final externalAudio = (_resolved?.hls?.audio ?? const [])
        .map(
          (a) => PlayerTrackItem(
            id: 'ext:${a.url}',
            title: a.name,
            language: a.language,
            uri: _apiClient.resolveStreamUrl(a.url),
          ),
        )
        .toList();

    final tracks = [..._playerAudioTracks, ...externalAudio];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tracce audio'),
        content: tracks.isEmpty
            ? const Text(
                'Nessuna traccia audio aggiuntiva rilevata.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              )
            : SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: tracks
                      .map(
                        (track) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(track.title),
                          subtitle: track.language != null
                              ? Text(
                                  track.language!.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                          trailing: _activeAudioId == track.id
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.textPrimary,
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_player.setAudioTrack(track));
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
      ),
    );
  }

  Future<void> _showSubtitlesDialog() async {
    final externalSubs = (_resolved?.hls?.subtitles ?? const [])
        .map(
          (s) => PlayerTrackItem(
            id: 'ext:${s.url}',
            title: s.name,
            language: s.language,
            uri: _apiClient.resolveStreamUrl(s.url),
          ),
        )
        .toList();

    final tracks = [..._playerSubtitleTracks, ...externalSubs];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sottotitoli'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disattiva'),
                trailing: (_activeSubtitleId == null || _activeSubtitleId == 'no')
                    ? const Icon(Icons.check, color: AppColors.textPrimary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_player.setSubtitleTrack(null));
                },
              ),
              ...tracks.map(
                (track) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(track.title),
                  subtitle: track.language != null
                      ? Text(
                          track.language!.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  trailing: _activeSubtitleId == track.id
                      ? const Icon(Icons.check, color: AppColors.textPrimary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_player.setSubtitleTrack(track));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = widget.media.kind == MediaKind.tv ||
        _resolved?.nextEpisode != null;
    final episodeLine = widget.media.kind == MediaKind.tv
        ? 'S$_season · E$_episode${_episodeTitle != null && _episodeTitle!.isNotEmpty ? " · $_episodeTitle" : ""}'
        : (widget.media.year ?? '');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.background),
            if (_errorMessage == null)
              Positioned.fill(child: _player.buildVideoView(context)),
            if (_errorMessage != null) _buildErrorView(),
            if (_errorMessage == null && (_isResolving || _isBuffering))
              const Center(
                child: CircularProgressIndicator(color: AppColors.textPrimary),
              ),
            if (_errorMessage == null)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: _buildOverlay(
                      episodeLine: episodeLine,
                      hasNext: hasNext,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.textSecondary,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Errore durante la riproduzione',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => _loadAndPlay(explicitTorrent: _selectedTorrent),
                    child: const Text('Riprova'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Indietro'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay({
    required String episodeLine,
    required bool hasNext,
  }) {
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = _duration.inMilliseconds > 0
        ? _position.inMilliseconds.toDouble().clamp(0.0, maxMs)
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.78),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.88),
          ],
          stops: const [0.0, 0.25, 0.65, 1.0],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _OverlayIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: 'Indietro',
                    onPressed: () {
                      if (_isFullscreen) {
                        _toggleFullscreen();
                      } else {
                        unawaited(_torrentGuard.stopActive());
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.media.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (episodeLine.isNotEmpty)
                          Text(
                            episodeLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _OverlayIconButton(
                    icon: Icons.audiotrack_rounded,
                    tooltip: 'Audio',
                    onPressed: _showAudioTracksDialog,
                  ),
                  const SizedBox(width: 8),
                  _OverlayIconButton(
                    icon: Icons.subtitles_outlined,
                    tooltip: 'Sottotitoli',
                    onPressed: _showSubtitlesDialog,
                  ),
                  const SizedBox(width: 8),
                  _OverlayIconButton(
                    icon: _isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    tooltip: 'Schermo intero',
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _OverlayIconButton(
                    icon: Icons.replay_10_rounded,
                    tooltip: 'Indietro 10s',
                    size: 50,
                    iconSize: 26,
                    onPressed: () {
                      final target = _position - const Duration(seconds: 10);
                      unawaited(
                        _player.seek(
                          target.isNegative ? Duration.zero : target,
                        ),
                      );
                      _startHideControlsTimer();
                    },
                  ),
                  const SizedBox(width: 28),
                  InkResponse(
                    onTap: () {
                      unawaited(_player.playOrPause());
                      _startHideControlsTimer();
                    },
                    radius: 36,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryAction,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: AppColors.onPrimaryAction,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  _OverlayIconButton(
                    icon: Icons.forward_10_rounded,
                    tooltip: 'Avanti 10s',
                    size: 50,
                    iconSize: 26,
                    onPressed: () {
                      unawaited(
                        _player.seek(_position + const Duration(seconds: 10)),
                      );
                      _startHideControlsTimer();
                    },
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: AppColors.textPrimary,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      value: posMs,
                      min: 0.0,
                      max: maxMs,
                      onChanged: (value) {
                        unawaited(
                          _player.seek(Duration(milliseconds: value.toInt())),
                        );
                        _startHideControlsTimer();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _showOptionsDialog,
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              AppColors.surface.withValues(alpha: 0.85),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(
                          'Opzioni · ${_selectedLanguage.toUpperCase()} · ${_selectedQuality.toUpperCase()} · ${_activeMode.toUpperCase()}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      if (hasNext)
                        FilledButton.icon(
                          onPressed: _playNextEpisode,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          icon: const Icon(Icons.skip_next_rounded, size: 18),
                          label: const Text('Prossimo episodio'),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.78),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: iconSize),
        ),
      ),
    );
  }
}
