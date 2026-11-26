import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/cast/cast_controller.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/cast_sheet.dart';

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
  final CastController? castController;

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
    this.castController,
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
  late final CastController _castController;

  late int _season;
  late int _episode;
  String? _episodeTitle;

  late String _selectedLanguage;
  late String _selectedQuality;
  late String _selectedSource;
  TorrentSource? _selectedTorrent;

  ResolvedStream? _resolved;
  String? _currentStreamUrl;
  Map<String, String>? _currentStreamHeaders;
  String? _currentSubtitleUrl;

  bool _isResolving = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isCasting = false;
  DateTime _lastCastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isDraggingSlider = false;
  bool _isModalOpen = false;
  String? _errorMessage;
  String _activeMode = 'hls';

  BoxFit _videoFit = BoxFit.contain;
  double _videoScale = 1.0;
  double _scaleBase = 1.0;
  String? _zoomBadgeText;
  Timer? _zoomBadgeTimer;

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
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );

    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;
    _torrentGuard =
        widget.torrentGuard ?? TorrentSessionGuard(apiClient: _apiClient);
    _player = (widget.playerFactory ?? MediaKitPlayerAdapter.new)();
    _castController = widget.castController ?? CastController.instance;
    _isCasting = _castController.isCasting;
    _castController.addListener(_onCastStateChanged);

    _season = widget.season;
    _episode = widget.episode;
    _episodeTitle = widget.episodeTitle;

    _selectedLanguage = widget.initialLanguage ?? _config.language;
    _selectedQuality = widget.initialQuality ?? _config.quality;
    _selectedSource = widget.initialSource ??
        (widget.initialTorrent != null ? 'torrent' : _config.source);
    _selectedTorrent = widget.initialTorrent;

    final savedSecs = _resolveInitialResumeSecs();
    if (savedSecs > 0) {
      _pendingResumePosition = Duration(seconds: savedSecs);
    }

    _setupPlayerListeners();
    _startProgressTimer();
    _startHideControlsTimer();
    unawaited(_loadAndPlay());
  }

  int _resolveInitialResumeSecs() {
    if (widget.initialPositionSecs > 0) {
      return widget.initialPositionSecs;
    }
    if (widget.media.kind == MediaKind.tv) {
      return _library.episodePositionSecs(
        widget.media.kind,
        widget.media.id,
        _season,
        _episode,
      );
    }
    return _library.entryFor(widget.media.kind, widget.media.id)?.positionSecs ??
        0;
  }

  void _setupPlayerListeners() {
    _subscriptions.addAll([
      _player.playingStream.listen((playing) {
        if (!mounted) return;
        setState(() => _isPlaying = playing);
        if (playing) {
          _pausedTorrentStopTimer?.cancel();
          if (_showControls) {
            _startHideControlsTimer();
          }
        }
      }),
      _player.bufferingStream.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
      _player.positionStream.listen((position) {
        if (mounted && !_isDraggingSlider) {
          setState(() => _position = position);
        }
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
      _castController.positionStream.listen((update) {
        if (!mounted) return;
        if (update.duration > Duration.zero) {
          _duration = update.duration;
        }
        if (update.position > Duration.zero) {
          setState(() => _position = update.position);
          final now = DateTime.now();
          if (now.difference(_lastCastProgressSave) >=
              const Duration(seconds: 8)) {
            _lastCastProgressSave = now;
            unawaited(_saveProgress(force: true, overridePos: update.position));
          }
        }
      }),
    ]);
  }

  void _onCastStateChanged() {
    if (!mounted) return;
    final casting = _castController.isCasting;
    if (casting != _isCasting) {
      setState(() => _isCasting = casting);
    }
  }

  Future<void> _openCastSheet() async {
    final mediaUrl = _currentStreamUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) return;

    _isModalOpen = true;
    _hideControlsTimer?.cancel();
    try {
      final castTitle = widget.media.kind == MediaKind.tv
          ? '${widget.media.title} · S$_season E$_episode'
          : widget.media.title;
      final isHls = _activeMode == 'hls' ||
          mediaUrl.toLowerCase().contains('.m3u8');

      await CastSheet.show(
        context,
        controller: _castController,
        mediaUrl: mediaUrl,
        title: castTitle,
        headers: _currentStreamHeaders,
        subtitleUrl: _currentSubtitleUrl,
        posterUrl: widget.media.poster ?? widget.media.backdrop,
        initialPosition: _position,
        isHls: isHls,
        onCastStarted: () {
          unawaited(_player.pause());
          if (mounted) {
            setState(() => _isCasting = true);
          }
        },
        onDisconnected: (Duration lastTvPosition) {
          if (mounted) {
            setState(() => _isCasting = false);
          }
          if (lastTvPosition > Duration.zero) {
            _position = lastTvPosition;
            unawaited(_saveProgress(force: true, overridePos: lastTvPosition));
            unawaited(_player.seek(lastTvPosition));
          }
          if (!_isPlaying) {
            unawaited(_player.playOrPause());
          }
        },
      );
    } finally {
      _isModalOpen = false;
      if (mounted && _showControls) {
        _startHideControlsTimer();
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
  }

  Future<void> _saveProgress({bool force = false, Duration? overridePos}) async {
    final posSecs = (overridePos ?? _position).inSeconds;
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
      _currentStreamUrl = streamUrl;
      _currentStreamHeaders = null;
      _currentSubtitleUrl = null;
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
        _currentStreamUrl = fullUrl;
        _currentStreamHeaders = null;
        _currentSubtitleUrl = null;
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
        final firstSub = resolved.hls?.subtitles.isNotEmpty == true
            ? _apiClient.resolveStreamUrl(resolved.hls!.subtitles.first.url)
            : null;
        _currentStreamUrl = fullUrl;
        _currentStreamHeaders = headers;
        _currentSubtitleUrl = firstSub;
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
      final nextSeason = next?.season ?? _season;
      final nextEpisode = next?.episode ?? (_episode + 1);
      final savedNextSecs = widget.media.kind == MediaKind.tv
          ? _library.episodePositionSecs(
              widget.media.kind,
              widget.media.id,
              nextSeason,
              nextEpisode,
            )
          : 0;

      if (mounted) {
        setState(() {
          _season = nextSeason;
          _episode = nextEpisode;
          _episodeTitle = next?.name;
          _position = Duration.zero;
          _duration = Duration.zero;
          _selectedTorrent = null;
          _playerAudioTracks = [];
          _playerSubtitleTracks = [];
        });
      }
      _pendingResumePosition =
          savedNextSecs > 0 ? Duration(seconds: savedNextSecs) : Duration.zero;
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
    if (_showControls) {
      _hideControlsTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      setState(() => _showControls = true);
      _startHideControlsTimer();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isDraggingSlider || _isModalOpen) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isDraggingSlider && !_isModalOpen && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleZoomFit() {
    setState(() {
      if (_videoFit == BoxFit.contain && _videoScale <= 1.01) {
        _videoFit = BoxFit.cover;
        _videoScale = 1.0;
        _showZoomBadge('Riempi');
      } else {
        _videoFit = BoxFit.contain;
        _videoScale = 1.0;
        _showZoomBadge('Adatta');
      }
    });
    _startHideControlsTimer();
  }

  void _showZoomBadge(String text) {
    _zoomBadgeTimer?.cancel();
    _zoomBadgeText = text;
    _zoomBadgeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _zoomBadgeText = null);
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
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _startHideControlsTimer();
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
    _castController.removeListener(_onCastStateChanged);
    _hideControlsTimer?.cancel();
    _zoomBadgeTimer?.cancel();
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

  Future<void> _showCinemaPanel({
    required String title,
    required WidgetBuilder bodyBuilder,
  }) async {
    _isModalOpen = true;
    _hideControlsTimer?.cancel();
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: title,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Chiudi',
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: bodyBuilder(ctx),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        transitionBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );
    } finally {
      _isModalOpen = false;
      if (mounted && _showControls) {
        _startHideControlsTimer();
      }
    }
  }

  Future<void> _showOptionsDialog() async {
    await _showCinemaPanel(
      title: 'Opzioni stream',
      bodyBuilder: (ctx) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          const Text(
            'Lingua',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
          const SizedBox(height: 22),
          const Text(
            'Qualità',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 22),
          const Text(
            'Sorgente',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
            const SizedBox(height: 24),
            const Text(
              'Torrent disponibili',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            ..._resolved!.torrents.take(8).map((t) {
              final active = _selectedTorrent?.infoHash == t.infoHash ||
                  (_activeMode == 'torrent' &&
                      _torrentGuard.activeInfoHash ==
                          t.infoHash.toLowerCase());
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: active ? AppColors.surfaceElevated : null,
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

    await _showCinemaPanel(
      title: 'Tracce audio',
      bodyBuilder: (ctx) {
        if (tracks.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              Text(
                'Nessuna traccia audio aggiuntiva rilevata.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: tracks.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: AppColors.border),
          itemBuilder: (context, index) {
            final track = tracks[index];
            final active = _activeAudioId == track.id;
            return ListTile(
              title: Text(
                track.title,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: track.language != null
                  ? Text(
                      track.language!.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    )
                  : null,
              trailing: active
                  ? const Icon(Icons.check, color: AppColors.textPrimary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_player.setAudioTrack(track));
              },
            );
          },
        );
      },
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

    await _showCinemaPanel(
      title: 'Sottotitoli',
      bodyBuilder: (ctx) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: tracks.length + 1,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isOff =
                _activeSubtitleId == null || _activeSubtitleId == 'no';
            return ListTile(
              title: const Text(
                'Disattiva',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              trailing: isOff
                  ? const Icon(Icons.check, color: AppColors.textPrimary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _currentSubtitleUrl = null;
                unawaited(_player.setSubtitleTrack(null));
              },
            );
          }
          final track = tracks[index - 1];
          final active = _activeSubtitleId == track.id;
          return ListTile(
            title: Text(
              track.title,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: track.language != null
                ? Text(
                    track.language!.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  )
                : null,
            trailing: active
                ? const Icon(Icons.check, color: AppColors.textPrimary)
                : null,
            onTap: () {
              Navigator.pop(ctx);
              if (track.isExternal) {
                _currentSubtitleUrl = track.uri;
              }
              unawaited(_player.setSubtitleTrack(track));
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasNext =
        widget.media.kind == MediaKind.tv || _resolved?.nextEpisode != null;
    final episodeLine = widget.media.kind == MediaKind.tv
        ? 'S$_season · E$_episode${_episodeTitle != null && _episodeTitle!.isNotEmpty ? " · $_episodeTitle" : ""}'
        : (widget.media.year ?? '');
    final showLoader = _errorMessage == null && (_isResolving || _isBuffering);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onScaleStart: (_) {
          _scaleBase = _videoScale;
        },
        onScaleUpdate: (details) {
          if (details.pointerCount < 2 && (details.scale - 1.0).abs() < 0.02) {
            return;
          }
          final next = (_scaleBase * details.scale).clamp(1.0, 2.5);
          if ((next - _videoScale).abs() > 0.01) {
            setState(() {
              _videoScale = next;
              _showZoomBadge('${_videoScale.toStringAsFixed(1)}x');
            });
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.background),
            if (_errorMessage == null)
              Positioned.fill(
                child: ClipRect(
                  child: Transform.scale(
                    scale: _videoScale,
                    child: _player.buildVideoView(context, fit: _videoFit),
                  ),
                ),
              ),
            if (_errorMessage != null) _buildErrorView(),
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
            if (showLoader)
              const Align(
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: SizedBox(
                    key: Key('player_loading_indicator'),
                    width: 76,
                    height: 76,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            if (_zoomBadgeText != null)
              Align(
                alignment: const Alignment(0, -0.58),
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      _zoomBadgeText!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
                    onPressed: () =>
                        _loadAndPlay(explicitTorrent: _selectedTorrent),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 430;
    final topBtnSize = compact ? 36.0 : 40.0;
    final topIconSize = compact ? 18.0 : 20.0;
    final topGap = compact ? 6.0 : 8.0;
    final isZoomed = _videoFit == BoxFit.cover || _videoScale > 1.01;

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Top bar
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 20,
                  10,
                  compact ? 12 : 20,
                  8,
                ),
                child: Row(
                  children: [
                    _OverlayIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Indietro',
                      size: topBtnSize,
                      iconSize: topIconSize,
                      onPressed: () {
                        if (_isFullscreen) {
                          _toggleFullscreen();
                        } else {
                          unawaited(_torrentGuard.stopActive());
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                    SizedBox(width: compact ? 8 : 12),
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
                              fontSize: 15,
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
                    SizedBox(width: topGap),
                    _OverlayIconButton(
                      key: const Key('player_cast_button'),
                      icon: _isCasting
                          ? Icons.cast_connected_rounded
                          : Icons.cast_rounded,
                      tooltip: _isCasting ? 'Trasmissione attiva' : 'Trasmetti',
                      size: topBtnSize,
                      iconSize: topIconSize,
                      onPressed: _openCastSheet,
                    ),
                    SizedBox(width: topGap),
                    _OverlayIconButton(
                      key: const Key('player_zoom_fit_button'),
                      icon: isZoomed
                          ? Icons.fit_screen_rounded
                          : Icons.aspect_ratio_rounded,
                      tooltip: isZoomed ? 'Adatta' : 'Riempi',
                      size: topBtnSize,
                      iconSize: topIconSize,
                      onPressed: _toggleZoomFit,
                    ),
                    SizedBox(width: topGap),
                    _OverlayIconButton(
                      icon: Icons.audiotrack_rounded,
                      tooltip: 'Audio',
                      size: topBtnSize,
                      iconSize: topIconSize,
                      onPressed: _showAudioTracksDialog,
                    ),
                    SizedBox(width: topGap),
                    _OverlayIconButton(
                      icon: Icons.subtitles_outlined,
                      tooltip: 'Sottotitoli',
                      size: topBtnSize,
                      iconSize: topIconSize,
                      onPressed: _showSubtitlesDialog,
                    ),
                    SizedBox(width: topGap),
                    _OverlayIconButton(
                      icon: _isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      tooltip: 'Schermo intero',
                      size: topBtnSize,
                      iconSize: topIconSize,
                      onPressed: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Center transport controls (exact screen center, concentric with spinner)
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                  key: const Key('player_play_pause_button'),
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
          ),
          // Bottom seek bar + responsive action pills
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 20,
                  8,
                  compact ? 14 : 20,
                  12,
                ),
                child: Column(
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
                        onChangeStart: (_) {
                          _isDraggingSlider = true;
                          _hideControlsTimer?.cancel();
                        },
                        onChanged: (value) {
                          setState(
                            () => _position = Duration(
                              milliseconds: value.toInt(),
                            ),
                          );
                        },
                        onChangeEnd: (value) {
                          _isDraggingSlider = false;
                          unawaited(
                            _player.seek(
                              Duration(milliseconds: value.toInt()),
                            ),
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
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _showOptionsDialog,
                            style: OutlinedButton.styleFrom(
                              backgroundColor:
                                  AppColors.surface.withValues(alpha: 0.85),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 15),
                            label: Text(
                              'Opzioni · ${_selectedLanguage.toUpperCase()} · ${_activeMode.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (hasNext)
                            FilledButton.icon(
                              onPressed: _playNextEpisode,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                size: 17,
                              ),
                              label: const Text(
                                'Prossimo episodio',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    super.key,
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
