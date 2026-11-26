import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/cast/cast_controller.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/desktop_window_controller.dart';
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
  final DesktopWindowController? windowController;
  final bool? isDesktopOverride;

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
    this.windowController,
    this.isDesktopOverride,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  static const List<double> _speedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  late final ApiClient _apiClient;
  late final ConfigService _config;
  late final LibraryService _library;
  late final TorrentSessionGuard _torrentGuard;
  late final PlayerAdapter _player;
  late final CastController _castController;
  late final DesktopWindowController _windowController;

  final FocusNode _keyboardFocusNode =
      FocusNode(debugLabel: 'video_player_shortcuts');

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
  bool _isDraggingVolume = false;
  bool _isHoveringControls = false;
  bool _showMobileVolumeBar = false;
  bool _showRemainingTime = false;
  bool _isModalOpen = false;
  String? _errorMessage;
  String _activeMode = 'hls';

  BoxFit _videoFit = BoxFit.contain;
  double _videoScale = 1.0;
  double _scaleBase = 1.0;
  String? _osdBadgeText;
  IconData? _osdBadgeIcon;
  Timer? _osdBadgeTimer;

  double _volume = 100.0;
  double _lastNonZeroVolume = 100.0;
  double _playbackRate = 1.0;

  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
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
  Timer? _volumePersistTimer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool get _isDesktop =>
      widget.isDesktopOverride ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_isDesktop) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }

    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;
    _torrentGuard =
        widget.torrentGuard ?? TorrentSessionGuard(apiClient: _apiClient);
    _player = (widget.playerFactory ?? MediaKitPlayerAdapter.new)();
    _castController = widget.castController ?? CastController.instance;
    _windowController =
        widget.windowController ?? DesktopWindowController.instance;
    _isFullscreen = _isDesktop && _windowController.isFullscreen;
    _windowController.addListener(_onWindowStateChanged);

    _isCasting = _castController.isCasting;
    _castController.addListener(_onCastStateChanged);

    _volume = _config.playerVolume.clamp(0.0, 100.0);
    _lastNonZeroVolume = _volume > 0.5 ? _volume : 100.0;
    unawaited(_player.setVolume(_volume));

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

  void _onWindowStateChanged() {
    if (!mounted || !_isDesktop) return;
    final next = _windowController.isFullscreen;
    if (next != _isFullscreen) {
      setState(() => _isFullscreen = next);
    }
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
      _player.bufferStream.listen((buffered) {
        if (mounted) setState(() => _bufferedPosition = buffered);
      }),
      _player.durationStream.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      _player.volumeStream.listen((vol) {
        if (!mounted || _isDraggingVolume) return;
        final clamped = vol.clamp(0.0, 100.0);
        setState(() {
          _volume = clamped;
          if (clamped > 0.5) {
            _lastNonZeroVolume = clamped;
          }
        });
      }),
      _player.rateStream.listen((rate) {
        if (mounted) {
          setState(() => _playbackRate = rate);
        }
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
      if (_isDesktop && mounted) {
        _keyboardFocusNode.requestFocus();
      }
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

  Future<void> _openMediaStream(
    String url, {
    Map<String, String>? httpHeaders,
    Duration start = Duration.zero,
  }) async {
    await _player.open(url, httpHeaders: httpHeaders, start: start);
    await _player.setVolume(_volume);
    if ((_playbackRate - 1.0).abs() > 0.01) {
      await _player.setRate(_playbackRate);
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
      await _openMediaStream(streamUrl, start: startAt);
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
        await _openMediaStream(fullUrl, start: startAt);
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
        await _openMediaStream(fullUrl, httpHeaders: headers, start: startAt);
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
          _bufferedPosition = Duration.zero;
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

  void _onCanvasTap() {
    if (_isDesktop) {
      _togglePlayPause(showOsd: true);
      if (!_showControls) {
        setState(() => _showControls = true);
      }
      _startHideControlsTimer();
    } else {
      _toggleControls();
    }
  }

  void _onPointerHover(PointerHoverEvent _) {
    if (!_isDesktop) return;
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideControlsTimer();
  }

  void _setHoveringControls(bool hovering) {
    if (_isHoveringControls == hovering) return;
    _isHoveringControls = hovering;
    if (hovering) {
      _hideControlsTimer?.cancel();
    } else if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isDraggingSlider ||
        _isDraggingVolume ||
        _isHoveringControls ||
        _isModalOpen) {
      return;
    }
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          !_isDraggingSlider &&
          !_isDraggingVolume &&
          !_isHoveringControls &&
          !_isModalOpen &&
          _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlayPause({bool showOsd = false}) {
    final nextPlaying = !_isPlaying;
    unawaited(_player.playOrPause());
    if (showOsd) {
      _showOsdBadge(
        nextPlaying ? 'Riproduci' : 'Pausa',
        icon: nextPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
      );
    }
    _startHideControlsTimer();
  }

  void _seekRelative(Duration delta, {bool showOsd = false}) {
    final target = _position + delta;
    final clamped = target.isNegative
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration
            ? _duration
            : target);
    setState(() => _position = clamped);
    unawaited(_player.seek(clamped));
    if (showOsd) {
      final secs = delta.inSeconds;
      _showOsdBadge(
        secs >= 0 ? '+${secs}s' : '${secs}s',
        icon: secs >= 0 ? Icons.forward_10_rounded : Icons.replay_10_rounded,
      );
    }
    _startHideControlsTimer();
  }

  void _seekToFraction(double fraction) {
    if (_duration <= Duration.zero) return;
    final targetMs =
        (_duration.inMilliseconds * fraction.clamp(0.0, 0.99)).round();
    final target = Duration(milliseconds: targetMs);
    setState(() => _position = target);
    unawaited(_player.seek(target));
    _showOsdBadge(
      _formatDuration(target),
      icon: Icons.schedule_rounded,
    );
    _startHideControlsTimer();
  }

  void _toggleZoomFit() {
    setState(() {
      if (_videoFit == BoxFit.contain && _videoScale <= 1.01) {
        _videoFit = BoxFit.cover;
        _videoScale = 1.0;
        _showOsdBadge('Riempi', icon: Icons.fit_screen_rounded);
      } else {
        _videoFit = BoxFit.contain;
        _videoScale = 1.0;
        _showOsdBadge('Adatta', icon: Icons.aspect_ratio_rounded);
      }
    });
    _startHideControlsTimer();
  }

  void _showOsdBadge(String text, {IconData? icon}) {
    _osdBadgeTimer?.cancel();
    setState(() {
      _osdBadgeText = text;
      _osdBadgeIcon = icon;
    });
    _osdBadgeTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) {
        setState(() {
          _osdBadgeText = null;
          _osdBadgeIcon = null;
        });
      }
    });
  }

  IconData _volumeIconFor(double vol) {
    if (vol <= 0.5) return Icons.volume_off_rounded;
    if (vol <= 50.0) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  void _setVolume(
    double value, {
    bool persist = false,
    bool showOsd = false,
    bool debouncePersist = false,
  }) {
    final clamped = value.clamp(0.0, 100.0);
    setState(() {
      _volume = clamped;
      if (clamped > 0.5) {
        _lastNonZeroVolume = clamped;
      }
      if (showOsd) {
        _osdBadgeText =
            clamped <= 0.5 ? 'Muto' : 'Volume ${clamped.round()}%';
        _osdBadgeIcon = _volumeIconFor(clamped);
      }
    });
    if (showOsd) {
      _osdBadgeTimer?.cancel();
      _osdBadgeTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) {
          setState(() {
            _osdBadgeText = null;
            _osdBadgeIcon = null;
          });
        }
      });
    }
    unawaited(_player.setVolume(clamped));
    if (persist) {
      _volumePersistTimer?.cancel();
      unawaited(_config.setPlayerVolume(clamped));
    } else if (debouncePersist) {
      _volumePersistTimer?.cancel();
      _volumePersistTimer = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_config.setPlayerVolume(clamped)),
      );
    }
  }

  void _toggleMute() {
    if (_volume > 0.5) {
      _lastNonZeroVolume = _volume;
      _setVolume(0.0, persist: true, showOsd: true);
    } else {
      final restore = _lastNonZeroVolume > 1.0 ? _lastNonZeroVolume : 100.0;
      _setVolume(restore, persist: true, showOsd: true);
    }
    _startHideControlsTimer();
  }

  void _stepVolume(double delta) {
    _setVolume(
      _volume + delta,
      debouncePersist: true,
      showOsd: true,
    );
    _startHideControlsTimer();
  }

  String _formatRate(double rate) {
    final rounded = (rate * 100).round() / 100;
    if ((rounded - rounded.roundToDouble()).abs() < 0.01) {
      return '${rounded.round()}x';
    }
    var str = rounded.toStringAsFixed(2);
    if (str.endsWith('0')) {
      str = str.substring(0, str.length - 1);
    }
    return '${str}x';
  }

  void _setPlaybackRate(double rate) {
    final clamped = rate.clamp(0.25, 4.0);
    setState(() => _playbackRate = clamped);
    unawaited(_player.setRate(clamped));
    _showOsdBadge(
      'Velocità ${_formatRate(clamped)}',
      icon: Icons.speed_rounded,
    );
    _startHideControlsTimer();
  }

  void _stepPlaybackRate(int delta) {
    var bestIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < _speedOptions.length; i++) {
      final dist = (_speedOptions[i] - _playbackRate).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    final nextIdx = (bestIdx + delta).clamp(0, _speedOptions.length - 1);
    _setPlaybackRate(_speedOptions[nextIdx]);
  }

  void _toggleFullscreen() {
    if (!_isDesktop) return;
    unawaited(_windowController.toggleFullscreen());
    _startHideControlsTimer();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isDesktop || _isModalOpen) return KeyEventResult.ignored;

    final isRepeat = event is KeyRepeatEvent;
    if (event is! KeyDownEvent && !isRepeat) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Repeatable transport & volume keys
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
      _seekRelative(Duration(seconds: shift ? -30 : -10), showOsd: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      _seekRelative(Duration(seconds: shift ? 30 : 10), showOsd: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _stepVolume(5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _stepVolume(-5);
      return KeyEventResult.handled;
    }

    if (isRepeat) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _togglePlayPause(showOsd: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_isFullscreen) {
        unawaited(_windowController.setFullscreen(false));
      } else {
        unawaited(_torrentGuard.stopActive());
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      _toggleZoomFit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      unawaited(_showAudioTracksDialog());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      unawaited(_showSubtitlesDialog());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      final hasNext =
          widget.media.kind == MediaKind.tv || _resolved?.nextEpisode != null;
      if (hasNext) {
        unawaited(_playNextEpisode());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.bracketLeft ||
        key == LogicalKeyboardKey.comma) {
      _stepPlaybackRate(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketRight ||
        key == LogicalKeyboardKey.period) {
      _stepPlaybackRate(1);
      return KeyEventResult.handled;
    }

    final fraction = _digitFractionForKey(key);
    if (fraction != null) {
      _seekToFraction(fraction);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  double? _digitFractionForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      return 0.0;
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      return 0.1;
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      return 0.2;
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      return 0.3;
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      return 0.4;
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      return 0.5;
    }
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      return 0.6;
    }
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      return 0.7;
    }
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      return 0.8;
    }
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      return 0.9;
    }
    return null;
  }

  String _formatDuration(Duration d) {
    final abs = d.isNegative ? Duration.zero : d;
    final hours = abs.inHours;
    final minutes = abs.inMinutes.remainder(60);
    final seconds = abs.inSeconds.remainder(60);
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
    _windowController.removeListener(_onWindowStateChanged);
    if (_isDesktop && _windowController.isFullscreen) {
      unawaited(_windowController.setFullscreen(false));
    }
    _castController.removeListener(_onCastStateChanged);
    _hideControlsTimer?.cancel();
    _osdBadgeTimer?.cancel();
    _progressTimer?.cancel();
    _pausedTorrentStopTimer?.cancel();
    _volumePersistTimer?.cancel();
    _keyboardFocusNode.dispose();
    unawaited(_saveProgress(force: true));
    unawaited(_torrentGuard.stopActive());
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    unawaited(_player.dispose());
    if (!_isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
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
      if (_isDesktop && mounted) {
        _keyboardFocusNode.requestFocus();
      }
      if (mounted && _showControls) {
        _startHideControlsTimer();
      }
    }
  }

  Future<void> _showSpeedDialog() async {
    await _showCinemaPanel(
      title: 'Velocità di riproduzione',
      bodyBuilder: (ctx) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _speedOptions.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, index) {
          final rate = _speedOptions[index];
          final active = (_playbackRate - rate).abs() < 0.01;
          return ListTile(
            title: Text(
              rate == 1.0 ? '1x (Normale)' : _formatRate(rate),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            trailing: active
                ? const Icon(Icons.check, color: AppColors.textPrimary)
                : null,
            onTap: () {
              Navigator.pop(ctx);
              _setPlaybackRate(rate);
            },
          );
        },
      ),
    );
  }

  Future<void> _showShortcutsDialog() async {
    const shortcuts = [
      ('Spazio / K', 'Riproduci o metti in pausa'),
      ('← / →  (J / L)', 'Indietro / Avanti di 10 secondi (Shift: 30s)'),
      ('↑ / ↓  o  Rotellina', 'Alza / Abbassa volume (±5%)'),
      ('M', 'Muto / Riattiva audio'),
      ('F / F11 / Doppio click', 'Schermo intero'),
      ('Esc', 'Esci da schermo intero o chiudi player'),
      ('Z', 'Adatta / Riempi schermo'),
      ('A / C', 'Tracce audio / Sottotitoli'),
      ('[ / ]', 'Diminuisci / Aumenta velocità'),
      ('0 – 9', 'Salta al 0% – 90% del video'),
      ('N', 'Prossimo episodio'),
    ];

    await _showCinemaPanel(
      title: 'Scorciatoie tastiera',
      bodyBuilder: (ctx) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: shortcuts.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, index) {
          final item = shortcuts[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    item.$1,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.$2,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
    final cursor = (_isDesktop && !_showControls && _isPlaying && !_isModalOpen)
        ? SystemMouseCursors.none
        : SystemMouseCursors.basic;

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: _isDesktop,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: MouseRegion(
          cursor: cursor,
          onHover: _onPointerHover,
          child: Listener(
            onPointerSignal: (event) {
              if (_isDesktop && event is PointerScrollEvent && !_isModalOpen) {
                final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
                _stepVolume(delta);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _scaleBase = _videoScale;
              },
              onScaleUpdate: (details) {
                if (details.pointerCount < 2 &&
                    (details.scale - 1.0).abs() < 0.02) {
                  return;
                }
                final next = (_scaleBase * details.scale).clamp(1.0, 2.5);
                if ((next - _videoScale).abs() > 0.01) {
                  setState(() {
                    _videoScale = next;
                  });
                  _showOsdBadge(
                    '${_videoScale.toStringAsFixed(1)}x',
                    icon: Icons.zoom_in_rounded,
                  );
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AppColors.background),
                  if (_errorMessage == null)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _onCanvasTap,
                        onDoubleTap: _isDesktop ? _toggleFullscreen : null,
                        child: ClipRect(
                          child: Transform.scale(
                            scale: _videoScale,
                            child: _player.buildVideoView(
                              context,
                              fit: _videoFit,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_errorMessage != null) _buildErrorView(),
                  if (_errorMessage == null)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: ExcludeFocus(
                          excluding: _isDesktop && !_isModalOpen,
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
                  if (_osdBadgeText != null)
                    Align(
                      alignment: const Alignment(0, -0.58),
                      child: IgnorePointer(
                        child: Container(
                          key: const Key('player_osd_badge'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_osdBadgeIcon != null) ...[
                                Icon(
                                  _osdBadgeIcon,
                                  color: AppColors.textPrimary,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                _osdBadgeText!,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 430;
    final topBtnSize = compact ? 36.0 : 40.0;
    final topIconSize = compact ? 18.0 : 20.0;
    final topGap = compact ? 6.0 : 8.0;
    final isZoomed = _videoFit == BoxFit.cover || _videoScale > 1.01;

    final remaining = _duration > _position
        ? _duration - _position
        : Duration.zero;
    final rightTimeLabel = _showRemainingTime && _duration > Duration.zero
        ? '-${_formatDuration(remaining)}'
        : _formatDuration(_duration);

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
          // Empty canvas area when controls are visible
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onCanvasTap,
              onDoubleTap: _isDesktop ? _toggleFullscreen : null,
            ),
          ),
          // Top bar
          Align(
            alignment: Alignment.topCenter,
            child: MouseRegion(
              onEnter: (_) => _setHoveringControls(true),
              onExit: (_) => _setHoveringControls(false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
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
                            if (_isDesktop && _isFullscreen) {
                              unawaited(
                                _windowController.setFullscreen(false),
                              );
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
                          tooltip:
                              _isCasting ? 'Trasmissione attiva' : 'Trasmetti',
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
                        if (_isDesktop) ...[
                          SizedBox(width: topGap),
                          _OverlayIconButton(
                            key: const Key('player_shortcuts_button'),
                            icon: Icons.keyboard_alt_outlined,
                            tooltip: 'Scorciatoie tastiera',
                            size: topBtnSize,
                            iconSize: topIconSize,
                            onPressed: _showShortcutsDialog,
                          ),
                          SizedBox(width: topGap),
                          _OverlayIconButton(
                            key: const Key('player_fullscreen_button'),
                            icon: _isFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            tooltip: _isFullscreen
                                ? 'Esci da schermo intero (F)'
                                : 'Schermo intero (F)',
                            size: topBtnSize,
                            iconSize: topIconSize,
                            onPressed: _toggleFullscreen,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Center transport controls (exact screen center, concentric with spinner)
          Align(
            alignment: Alignment.center,
            child: MouseRegion(
              onEnter: (_) => _setHoveringControls(true),
              onExit: (_) => _setHoveringControls(false),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OverlayIconButton(
                    icon: Icons.replay_10_rounded,
                    tooltip: 'Indietro 10s',
                    size: 50,
                    iconSize: 26,
                    onPressed: () =>
                        _seekRelative(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 28),
                  InkResponse(
                    key: const Key('player_play_pause_button'),
                    onTap: () => _togglePlayPause(),
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
                    onPressed: () =>
                        _seekRelative(const Duration(seconds: 10)),
                  ),
                ],
              ),
            ),
          ),
          // Bottom seek bar + volume + action dock
          Align(
            alignment: Alignment.bottomCenter,
            child: MouseRegion(
              onEnter: (_) => _setHoveringControls(true),
              onExit: (_) => _setHoveringControls(false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
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
                        if (!_isDesktop && _showMobileVolumeBar) ...[
                          _buildMobileVolumeBar(),
                          const SizedBox(height: 8),
                        ],
                        _CinemaSeekBar(
                          position: _position,
                          buffered: _bufferedPosition,
                          duration: _duration,
                          isDesktop: _isDesktop,
                          formatDuration: _formatDuration,
                          onSeekStart: () {
                            _isDraggingSlider = true;
                            _hideControlsTimer?.cancel();
                          },
                          onSeekChanged: (pos) {
                            setState(() => _position = pos);
                          },
                          onSeekEnd: (pos) {
                            _isDraggingSlider = false;
                            unawaited(_player.seek(pos));
                            _startHideControlsTimer();
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () {
                                  setState(
                                    () => _showRemainingTime =
                                        !_showRemainingTime,
                                  );
                                  _startHideControlsTimer();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    rightTimeLabel,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _isDesktop
                            ? _buildDesktopBottomActions(hasNext: hasNext)
                            : _buildMobileBottomActions(hasNext: hasNext),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopBottomActions({required bool hasNext}) {
    return Row(
      children: [
        _buildDesktopBottomTransport(),
        const SizedBox(width: 10),
        _buildDesktopVolumeCluster(),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSpeedButton(),
                  const SizedBox(width: 8),
                  _buildOptionsButton(),
                  if (hasNext) ...[
                    const SizedBox(width: 8),
                    _buildNextEpisodeButton(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopBottomTransport() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Indietro 10s (←)',
            child: InkWell(
              key: const Key('desktop_seek_back_button'),
              onTap: () => _seekRelative(const Duration(seconds: -10)),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(
                  Icons.replay_10_rounded,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
          Tooltip(
            message: _isPlaying ? 'Pausa (Spazio)' : 'Riproduci (Spazio)',
            child: InkWell(
              key: const Key('desktop_play_pause_button'),
              onTap: () => _togglePlayPause(),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Avanti 10s (→)',
            child: InkWell(
              key: const Key('desktop_seek_forward_button'),
              onTap: () => _seekRelative(const Duration(seconds: 10)),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(
                  Icons.forward_10_rounded,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopVolumeCluster() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: _volume <= 0.5
                ? 'Riattiva audio (M)'
                : 'Muto (M)',
            child: InkWell(
              key: const Key('player_mute_button'),
              onTap: _toggleMute,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  _volumeIconFor(_volume),
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            height: 28,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5.5,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 11,
                ),
                activeTrackColor: AppColors.textPrimary,
                inactiveTrackColor: Colors.white24,
                thumbColor: AppColors.textPrimary,
                overlayColor: Colors.white24,
              ),
              child: Slider(
                key: const Key('player_volume_slider'),
                value: _volume,
                min: 0.0,
                max: 100.0,
                onChangeStart: (_) {
                  _isDraggingVolume = true;
                  _hideControlsTimer?.cancel();
                },
                onChanged: (val) => _setVolume(val),
                onChangeEnd: (val) {
                  _isDraggingVolume = false;
                  _setVolume(val, persist: true);
                  _startHideControlsTimer();
                },
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${_volume.round()}%',
              key: const Key('player_volume_label'),
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildMobileBottomActions({required bool hasNext}) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildOptionsButton(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSpeedButton(),
              _buildMobileVolumeButton(),
              if (hasNext) _buildNextEpisodeButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileVolumeButton() {
    return OutlinedButton.icon(
      key: const Key('player_volume_button'),
      onPressed: () {
        setState(() => _showMobileVolumeBar = !_showMobileVolumeBar);
        _startHideControlsTimer();
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: _showMobileVolumeBar
            ? AppColors.surfaceElevated
            : AppColors.surface.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(_volumeIconFor(_volume), size: 15),
      label: Text(
        '${_volume.round()}%',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildMobileVolumeBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('player_mute_button'),
            tooltip: _volume <= 0.5 ? 'Riattiva audio' : 'Muto',
            visualDensity: VisualDensity.compact,
            onPressed: _toggleMute,
            icon: Icon(
              _volumeIconFor(_volume),
              color: AppColors.textPrimary,
              size: 18,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 12,
                ),
                activeTrackColor: AppColors.textPrimary,
                inactiveTrackColor: Colors.white24,
                thumbColor: AppColors.textPrimary,
                overlayColor: Colors.white24,
              ),
              child: Slider(
                key: const Key('player_volume_slider'),
                value: _volume,
                min: 0.0,
                max: 100.0,
                onChangeStart: (_) {
                  _isDraggingVolume = true;
                  _hideControlsTimer?.cancel();
                },
                onChanged: (val) => _setVolume(val),
                onChangeEnd: (val) {
                  _isDraggingVolume = false;
                  _setVolume(val, persist: true);
                  _startHideControlsTimer();
                },
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${_volume.round()}%',
              key: const Key('player_volume_label'),
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedButton() {
    return OutlinedButton.icon(
      key: const Key('player_speed_button'),
      onPressed: _showSpeedDialog,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.speed_rounded, size: 15),
      label: Text(
        _formatRate(_playbackRate),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildOptionsButton() {
    return OutlinedButton.icon(
      onPressed: _showOptionsDialog,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.tune_rounded, size: 15),
      label: Text(
        'Opzioni · ${_selectedLanguage.toUpperCase()} · ${_activeMode.toUpperCase()}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildNextEpisodeButton() {
    return FilledButton.icon(
      onPressed: _playNextEpisode,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.skip_next_rounded, size: 17),
      label: const Text(
        'Prossimo episodio',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12),
      ),
    );
  }
}

class _CinemaSeekBar extends StatefulWidget {
  final Duration position;
  final Duration buffered;
  final Duration duration;
  final bool isDesktop;
  final String Function(Duration) formatDuration;
  final VoidCallback onSeekStart;
  final ValueChanged<Duration> onSeekChanged;
  final ValueChanged<Duration> onSeekEnd;

  const _CinemaSeekBar({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.isDesktop,
    required this.formatDuration,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  @override
  State<_CinemaSeekBar> createState() => _CinemaSeekBarState();
}

class _CinemaSeekBarState extends State<_CinemaSeekBar> {
  bool _hovered = false;
  bool _dragging = false;
  double? _hoverFraction;

  Duration _durationForFraction(double fraction) {
    final totalMs = widget.duration.inMilliseconds;
    if (totalMs <= 0) return Duration.zero;
    return Duration(
      milliseconds: (totalMs * fraction.clamp(0.0, 1.0)).round(),
    );
  }

  double _fractionFromLocalDx(double dx, double width) {
    if (width <= 0) return 0.0;
    return (dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    final posFraction = totalMs > 0
        ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final bufFraction = totalMs > 0
        ? (widget.buffered.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final active = _hovered || _dragging;
    final trackHeight = active ? 5.5 : 3.5;
    final thumbRadius = active ? 7.0 : 5.5;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showPreview =
            widget.isDesktop && _hovered && _hoverFraction != null && totalMs > 0;

        return MouseRegion(
          cursor: totalMs > 0
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _hoverFraction = null;
          }),
          onHover: (event) {
            setState(() {
              _hoverFraction =
                  _fractionFromLocalDx(event.localPosition.dx, width);
            });
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: totalMs > 0
                ? (details) {
                    _dragging = true;
                    widget.onSeekStart();
                    final frac =
                        _fractionFromLocalDx(details.localPosition.dx, width);
                    widget.onSeekChanged(_durationForFraction(frac));
                  }
                : null,
            onHorizontalDragUpdate: totalMs > 0
                ? (details) {
                    final frac =
                        _fractionFromLocalDx(details.localPosition.dx, width);
                    setState(() => _hoverFraction = frac);
                    widget.onSeekChanged(_durationForFraction(frac));
                  }
                : null,
            onHorizontalDragEnd: totalMs > 0
                ? (_) {
                    _dragging = false;
                    widget.onSeekEnd(widget.position);
                  }
                : null,
            onHorizontalDragCancel: totalMs > 0
                ? () {
                    _dragging = false;
                    widget.onSeekEnd(widget.position);
                  }
                : null,
            onTapDown: totalMs > 0
                ? (details) {
                    final frac =
                        _fractionFromLocalDx(details.localPosition.dx, width);
                    final target = _durationForFraction(frac);
                    widget.onSeekStart();
                    widget.onSeekChanged(target);
                    widget.onSeekEnd(target);
                  }
                : null,
            child: SizedBox(
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  if (showPreview)
                    Positioned(
                      bottom: 28,
                      left: (_hoverFraction! * width - 28)
                          .clamp(0.0, (width - 56).clamp(0.0, double.infinity)),
                      child: IgnorePointer(
                        child: Container(
                          width: 56,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.formatDuration(
                              _durationForFraction(_hoverFraction!),
                            ),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Base track
                  Container(
                    width: width,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(trackHeight / 2),
                    ),
                  ),
                  // Buffered track
                  if (bufFraction > 0)
                    Container(
                      width: width * bufFraction,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: Colors.white38,
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                  // Played track
                  if (posFraction > 0)
                    Container(
                      width: width * posFraction,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                  // Thumb
                  Positioned(
                    left: (posFraction * width - thumbRadius)
                        .clamp(0.0, (width - thumbRadius * 2).clamp(0.0, width)),
                    child: Container(
                      width: thumbRadius * 2,
                      height: thumbRadius * 2,
                      decoration: const BoxDecoration(
                        color: AppColors.textPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
