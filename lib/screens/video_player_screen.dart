import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:onlystream/models/video_model.dart' as model;

class VideoPlayerScreen extends StatefulWidget {
  final model.Video video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late model.Video currentVideo;

  // media_kit player e controller
  late final Player _player;
  late final VideoController _videoController;

  String _selectedLanguage = 'it';

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _hasError = false;
  String _errorMessage = '';

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Tracce audio e sottotitoli dal player
  List<AudioTrack> _audioTracks = [];
  List<SubtitleTrack> _subtitleTracks = [];
  AudioTrack? _activeAudioTrack;

  Timer? _hideControlsTimer;

  // Sottoscrizioni stream
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    currentVideo = widget.video;

    // Crea il player e il video controller
    _player = Player();
    _videoController = VideoController(_player);

    _setupListeners();
    _openMedia();
    _startHideControlsTimer();
  }

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
        if (completed && currentVideo.hasNext) {
          _playNextEpisode();
        }
      }),
      _player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() {
            _audioTracks = tracks.audio;
            _subtitleTracks = tracks.subtitle;
          });
          debugPrint('🔊 Tracce audio: ${tracks.audio.length}');
          for (final t in tracks.audio) {
            debugPrint('  └─ ${t.title ?? t.language ?? t.id}');
          }
          debugPrint('📝 Tracce sottotitoli: ${tracks.subtitle.length}');
        }
      }),
      _player.stream.track.listen((track) {
        if (mounted) {
          setState(() => _activeAudioTrack = track.audio);
        }
      }),
      _player.stream.error.listen((error) {
        debugPrint('❌ Errore player: $error');
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = error;
          });
        }
      }),
    ]);
  }

  void _openMedia() {
    final streamUrl = currentVideo.getStreamUrl(language: _selectedLanguage);
    debugPrint('🎥 Apertura stream M3U8/HLS');
    debugPrint('🔗 URL: $streamUrl');

    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    _player.open(Media(streamUrl));
  }

  void _changeLanguage(String language) {
    debugPrint('🌐 Cambio lingua a: ${language.toUpperCase()}');

    setState(() {
      _selectedLanguage = language;
      _audioTracks = [];
      _activeAudioTrack = null;
    });

    final newStreamUrl = currentVideo.getStreamUrl(language: language);
    _player.open(Media(newStreamUrl));
  }

  void _changeAudioTrack(AudioTrack track) {
    debugPrint('🔊 Cambio traccia audio a: ${track.title ?? track.id}');
    _player.setAudioTrack(track);
  }

  void _playNextEpisode() {
    final nextUrl = currentVideo.getNextStreamUrl(language: _selectedLanguage);

    if (nextUrl != null) {
      debugPrint('[Player] Avvio episodio successivo: $nextUrl');

      setState(() {
        currentVideo = model.Video(
          id: currentVideo.id,
          title: currentVideo.title,
          type: currentVideo.type,
          audioTracks: currentVideo.audioTracks,
          currentEpisode: currentVideo.nextEpisode,
          nextEpisode: null,
          hasNext: false,
        );
        _audioTracks = [];
        _activeAudioTrack = null;
      });

      _player.open(Media(nextUrl));
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessun episodio successivo disponibile'),
          ),
        );
      }
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
    // Ripristina orientamento
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isFullscreen
            ? _buildPlayer()
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildPlayer(),
                    _buildVideoInfo(),
                    _buildLanguageSelector(),
                    const SizedBox(height: 16),
                    _buildAudioTrackSelector(),
                    const SizedBox(height: 16),
                    _buildNextEpisodeButton(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }

  // 🎬 PLAYER
  Widget _buildPlayer() {
    return GestureDetector(
      onTap: _toggleControls,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          children: [
            // Sfondo nero
            Container(color: Colors.black),
            // Errore
            if (_hasError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage.isNotEmpty
                            ? _errorMessage
                            : 'Errore nel caricamento del video',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _openMedia,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Riprova'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Video
            if (!_hasError)
              Video(controller: _videoController, controls: NoVideoControls),
            // Buffering indicator
            if (!_hasError && _isBuffering)
              const Center(child: CircularProgressIndicator(color: Colors.red)),
            // Overlay controlli
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

  // 📺 INFO VIDEO
  Widget _buildVideoInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentVideo.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (currentVideo.type == "series" &&
              currentVideo.currentEpisode != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                "S${currentVideo.currentEpisode!.season.toString().padLeft(2, '0')}E${currentVideo.currentEpisode!.number.toString().padLeft(2, '0')} - ${currentVideo.currentEpisode!.title ?? 'Episodio'}",
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  // 🌐 SELEZIONE LINGUA (dal modello Video)
  Widget _buildLanguageSelector() {
    if (currentVideo.audioTracks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lingua audio:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: currentVideo.audioTracks
                  .map(
                    (track) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ElevatedButton(
                        onPressed: () => _changeLanguage(track.code),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedLanguage == track.code
                              ? Colors.red
                              : Colors.grey[700],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          track.language,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 🔊 SELEZIONE TRACCIA AUDIO (dal player - tracce nel file M3U8)
  Widget _buildAudioTrackSelector() {
    // Filtra la traccia "no" (disattiva) e "auto"
    final tracks = _audioTracks
        .where((t) => t != AudioTrack.no() && t != AudioTrack.auto())
        .toList();
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Traccia audio (stream):',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tracks
                  .map(
                    (track) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ElevatedButton(
                        onPressed: () => _changeAudioTrack(track),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _activeAudioTrack == track
                              ? Colors.red
                              : Colors.grey[700],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          track.title ?? track.language ?? 'Audio ${track.id}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextEpisodeButton() {
    if (currentVideo.type != "series" ||
        currentVideo.nextEpisode == null ||
        !currentVideo.hasNext) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _playNextEpisode,
          icon: const Icon(Icons.skip_next),
          label: Text(
            "Prossimo: S${currentVideo.nextEpisode!.season.toString().padLeft(2, '0')}E${currentVideo.nextEpisode!.number.toString().padLeft(2, '0')}",
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 12),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  OVERLAY CONTROLLI
  // ═══════════════════════════════════════════════

  Widget _buildPlayerControls() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(0, 0, 0, 0.6),
            Color.fromRGBO(0, 0, 0, 0.0),
            Color.fromRGBO(0, 0, 0, 0.0),
            Color.fromRGBO(0, 0, 0, 0.7),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top bar
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
                    currentVideo.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Center - Play/Pause
          IconButton(
            iconSize: 64,
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white,
            ),
            onPressed: () {
              _player.playOrPause();
              _startHideControlsTimer();
            },
          ),

          // Bottom bar - Seek + controlli
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seek bar
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
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                          activeTrackColor: Colors.red,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.red,
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
              // Bottom controls
              Padding(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  bottom: 8.0,
                ),
                child: Row(
                  children: [
                    // Volume
                    IconButton(
                      icon: const Icon(Icons.volume_up, color: Colors.white),
                      onPressed: () => _player.setVolume(100.0),
                    ),

                    const Spacer(),

                    // Sottotitoli
                    IconButton(
                      icon: const Icon(Icons.subtitles, color: Colors.white),
                      onPressed: _showSubtitlesDialog,
                    ),

                    // Fullscreen
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

  void _showSubtitlesDialog() {
    // Filtra la traccia "no" e "auto"
    final tracks = _subtitleTracks
        .where((t) => t != SubtitleTrack.no() && t != SubtitleTrack.auto())
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
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
