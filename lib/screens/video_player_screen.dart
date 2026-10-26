import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:onlystream/models/video_model.dart' as model;
import 'package:onlystream/services/download_service.dart';
import 'package:onlystream/services/server_config_service.dart';
import 'package:onlystream/services/video_service.dart';
import 'package:onlystream/utils/torrent_launcher.dart';

// [Video_Player_Screen]
class VideoPlayerScreen extends StatefulWidget {
  final model.Video video;
  final String? initialLanguage;
  final String? initialQuality;
  final String? initialSource;

  const VideoPlayerScreen({
    super.key,
    required this.video,
    this.initialLanguage,
    this.initialQuality,
    this.initialSource,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // [State_Variables]
  late model.Video currentVideo;

  late final Player _player;
  late final VideoController _videoController;

  late String _selectedLanguage;
  late String _selectedQuality;
  late String _selectedSource;

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _hasError = false;
  String _errorMessage = '';

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  List<AudioTrack> _audioTracks = [];
  List<SubtitleTrack> _subtitleTracks = [];
  AudioTrack? _activeAudioTrack;

  Timer? _hideControlsTimer;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    currentVideo = widget.video;
    _selectedLanguage =
        widget.initialLanguage ?? ServerConfigService.instance.defaultLanguage;
    _selectedQuality =
        widget.initialQuality ?? ServerConfigService.instance.preferredQuality;
    _selectedSource =
        widget.initialSource ?? ServerConfigService.instance.preferredSource;

    _player = Player();
    _videoController = VideoController(_player);

    _setupListeners();
    _openMedia();
    _startHideControlsTimer();
  }

  // [Stream_Listeners]
  void _setupListeners() {
    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
      _player.stream.position.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
      _player.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      _player.stream.completed.listen((completed) {
        if (completed &&
            (currentVideo.isSeries ||
                currentVideo.isAnime ||
                currentVideo.hasNext)) {
          _playNextEpisode();
        }
      }),
      _player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() {
            _audioTracks = tracks.audio;
            _subtitleTracks = tracks.subtitle;
          });
        }
      }),
      _player.stream.track.listen((track) {
        if (mounted) {
          setState(() => _activeAudioTrack = track.audio);
        }
      }),
      _player.stream.error.listen((error) {
        debugPrint('[PlayerError] $error');
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = error;
          });
        }
      }),
    ]);
  }

  // [Media_Control_Methods]
  void _openMedia() {
    final streamUrl = currentVideo.getStreamUrl(
      language: _selectedLanguage,
      quality: _selectedQuality,
      source: _selectedSource,
    );
    debugPrint('[MediaStream] Opening stream URL: $streamUrl');

    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    if (currentVideo.localFilePath != null &&
        currentVideo.localFilePath!.isNotEmpty) {
      final f = File(currentVideo.localFilePath!);
      if (f.existsSync()) {
        _player.open(Media(f.path));
        return;
      }
    }

    _player.open(Media(streamUrl));
  }

  void _changeAudioTrack(AudioTrack track) {
    _player.setAudioTrack(track);
  }

  Future<void> _playNextEpisode() async {
    final currentEp = currentVideo.currentEpisode ?? currentVideo.nextEpisode;
    final int season = currentEp?.season ?? 1;
    final int episode = currentEp?.number ?? 1;

    final fetchedVideo = await VideoService.fetchNextEpisode(
      tvId: currentVideo.id,
      season: season,
      episode: episode,
      language: _selectedLanguage,
      isAnime: currentVideo.isAnime,
    );

    if (!mounted) return;

    if (fetchedVideo != null) {
      setState(() {
        currentVideo = fetchedVideo;
        _audioTracks = [];
        _activeAudioTrack = null;
      });
    } else {
      final nextSeason = currentVideo.nextEpisode?.season ?? season;
      final nextEpNumber = currentVideo.nextEpisode?.number ?? (episode + 1);

      setState(() {
        currentVideo = model.Video(
          id: currentVideo.id,
          title: currentVideo.title,
          type: currentVideo.type,
          audioTracks: currentVideo.audioTracks,
          currentEpisode: model.Episode(
            season: nextSeason,
            number: nextEpNumber,
            title: 'Episodio $nextEpNumber',
          ),
          nextEpisode: model.Episode(
            season: nextSeason,
            number: nextEpNumber + 1,
            title: 'Episodio ${nextEpNumber + 1}',
          ),
          hasNext: true,
        );
        _audioTracks = [];
        _activeAudioTrack = null;
      });
    }

    DownloadService.instance.addToHistory(currentVideo);
    _openMedia();
  }

  Future<void> _downloadCurrentFromPlayer() async {
    final kind = currentVideo.isAnime
        ? model.MediaKind.anime
        : (currentVideo.isSeries ? model.MediaKind.tv : model.MediaKind.movie);
    await DownloadService.instance.enqueueSingle(
      mediaId: currentVideo.id,
      title: currentVideo.title,
      mediaKind: kind,
      season: currentVideo.currentEpisode?.season ?? 1,
      episode: currentVideo.currentEpisode?.number ?? 1,
      language: _selectedLanguage,
      quality: _selectedQuality,
      posterUrl: currentVideo.posterUrl,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF06B6D4),
          content: Text(
            'Download avviato per ${currentVideo.title} (${_selectedQuality.toUpperCase()})!',
          ),
        ),
      );
    }
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // [UI_Build]
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: _buildPlayer(),
        ),
      ),
    );
  }

  // [Player_Container]
  Widget _buildPlayer() {
    return GestureDetector(
      onTap: _toggleControls,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          children: [
            Container(color: Colors.black),
            if (_hasError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFF43F5E),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage.isNotEmpty
                            ? _errorMessage
                            : 'Errore nel caricamento dello stream da ${ServerConfigService.instance.baseUrl}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _openMedia,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Riprova'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF06B6D4),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Torna Indietro'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (!_hasError)
              Video(controller: _videoController, controls: NoVideoControls),
            if (!_hasError && _isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF06B6D4)),
              ),
            if (!_hasError && _showControls)
              AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 300),
                child: _buildPlayerControls(),
              ),
          ],
        ),
      ),
    );
  }

  // [Player_Overlay_Controls]
  Widget _buildPlayerControls() {
    final epSubtitle = currentVideo.currentEpisode != null
        ? (currentVideo.isAnime
            ? ' • Ep ${currentVideo.currentEpisode!.number}'
            : ' • S${currentVideo.currentEpisode!.season}E${currentVideo.currentEpisode!.number}${currentVideo.currentEpisode!.title != null ? " (${currentVideo.currentEpisode!.title})" : ""}')
        : '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(0, 0, 0, 0.72),
            Color.fromRGBO(0, 0, 0, 0.0),
            Color.fromRGBO(0, 0, 0, 0.0),
            Color.fromRGBO(0, 0, 0, 0.78),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // [Top_Bar]
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    if (_isFullscreen) {
                      _toggleFullscreen();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    '${currentVideo.title}$epSubtitle',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Quick Quality Badge
                ActionChip(
                  backgroundColor: Colors.black54,
                  side: const BorderSide(color: Color(0xFF06B6D4)),
                  label: Text(
                    '${_selectedQuality.toUpperCase()} • ${_selectedLanguage.toUpperCase()}',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _showQualityAndLanguageDialog,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Scarica questo video (MP4)',
                  icon: const Icon(
                    Icons.download_for_offline_rounded,
                    color: Color(0xFF38BDF8),
                  ),
                  onPressed: _downloadCurrentFromPlayer,
                ),
              ],
            ),
          ),

          // [Center_Play_Pause_Button]
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white70),
                onPressed: () {
                  final target = _position - const Duration(seconds: 10);
                  _player.seek(target.isNegative ? Duration.zero : target);
                  _startHideControlsTimer();
                },
              ),
              const SizedBox(width: 20),
              IconButton(
                iconSize: 64,
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.white,
                ),
                onPressed: () {
                  _player.playOrPause();
                  _startHideControlsTimer();
                },
              ),
              const SizedBox(width: 20),
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white70),
                onPressed: () {
                  _player.seek(_position + const Duration(seconds: 10));
                  _startHideControlsTimer();
                },
              ),
            ],
          ),

          // [Bottom_Bar]
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // [Seek_Bar]
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: const SliderThemeData(
                          trackHeight: 3,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                          activeTrackColor: Color(0xFF06B6D4),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Color(0xFF38BDF8),
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds > 0
                              ? _position.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  _duration.inMilliseconds.toDouble(),
                                )
                              : 0.0,
                          min: 0.0,
                          max: _duration.inMilliseconds > 0
                              ? _duration.inMilliseconds.toDouble()
                              : 1.0,
                          onChanged: (value) {
                            _player.seek(Duration(milliseconds: value.toInt()));
                            _startHideControlsTimer();
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // [Bottom_Action_Controls]
              Padding(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  bottom: 8.0,
                ),
                child: Row(
                  children: [
                    // [Volume_Control]
                    IconButton(
                      icon: const Icon(Icons.volume_up, color: Colors.white),
                      onPressed: () => _player.setVolume(100.0),
                    ),
                    IconButton(
                      tooltip: 'Copia URL Stream M3U8',
                      icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                      onPressed: () async {
                        final url = currentVideo.getStreamUrl(
                          language: _selectedLanguage,
                          quality: _selectedQuality,
                          source: _selectedSource,
                        );
                        await TorrentLauncher.copyToClipboard(url);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('URL copiato: $url')),
                          );
                        }
                      },
                    ),

                    const Spacer(),

                    // [Next_Episode_Control]
                    if (currentVideo.isSeries ||
                        currentVideo.isAnime ||
                        currentVideo.hasNext)
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        tooltip: 'Prossimo Episodio',
                        onPressed: _playNextEpisode,
                      ),

                    // [Quality_&_Language_Control]
                    IconButton(
                      icon: const Icon(Icons.high_quality_rounded, color: Colors.white),
                      tooltip: 'Qualità & Sorgente API',
                      onPressed: _showQualityAndLanguageDialog,
                    ),

                    // [Audio_Track_Control]
                    IconButton(
                      icon: const Icon(Icons.audiotrack, color: Colors.white),
                      tooltip: 'Tracce Audio HLS',
                      onPressed: _showAudioTracksDialog,
                    ),

                    // [Subtitles_Control]
                    IconButton(
                      icon: const Icon(Icons.subtitles, color: Colors.white),
                      tooltip: 'Sottotitoli',
                      onPressed: _showSubtitlesDialog,
                    ),

                    // [Fullscreen_Control]
                    IconButton(
                      icon: Icon(
                        _isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                      ),
                      onPressed: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQualityAndLanguageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121722),
        title: const Text(
          'Qualità Video & Lingua API',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Risoluzione Stream HLS:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['best', '2160p', '1080p', '720p', '480p'].map((q) {
                final active = _selectedQuality == q;
                return ChoiceChip(
                  label: Text(q == 'best' ? 'Auto (Max)' : q.toUpperCase()),
                  selected: active,
                  selectedColor: const Color(0xFF06B6D4),
                  onSelected: (_) {
                    setState(() => _selectedQuality = q);
                    Navigator.pop(ctx);
                    _openMedia();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Lingua Audio Richiesta al Server:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: {
                'it': '🇮🇹 Italiano',
                'en': '🇬🇧 English',
                'ja': '🇯🇵 Japanese',
              }.entries.map((e) {
                final active = _selectedLanguage == e.key;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: active,
                  selectedColor: const Color(0xFF06B6D4),
                  onSelected: (_) {
                    setState(() => _selectedLanguage = e.key);
                    Navigator.pop(ctx);
                    _openMedia();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // [Audio_Tracks_Dialog]
  void _showAudioTracksDialog() {
    final tracks = _audioTracks
        .where((t) => t != AudioTrack.no() && t != AudioTrack.auto())
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121722),
        title: const Text('Tracce Audio', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: tracks.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Nessuna traccia audio secondaria rilevata',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                ]
              : tracks
                  .map(
                    (track) => ListTile(
                      title: Text(
                        track.title ?? track.language ?? 'Audio ${track.id}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: _activeAudioTrack == track
                          ? const Icon(Icons.check, color: Color(0xFF06B6D4))
                          : null,
                      onTap: () {
                        _changeAudioTrack(track);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }

  // [Subtitles_Dialog]
  void _showSubtitlesDialog() {
    final tracks = _subtitleTracks
        .where((t) => t != SubtitleTrack.no() && t != SubtitleTrack.auto())
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121722),
        title: const Text('Sottotitoli', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                'Disattiva',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                _player.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(context);
              },
            ),
            ...tracks.map(
              (track) => ListTile(
                title: Text(
                  track.title ?? track.language ?? 'Sub ${track.id}',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _player.setSubtitleTrack(track);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
