import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:onlystream/models/video_model.dart' as model;

class VideoPlayerScreen extends StatefulWidget {
  final model.Video video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late model.Video currentVideo;
  VlcPlayerController? _vlcPlayerController;

  String _selectedLanguage = 'it';
  Map<int, String> _availableAudioTracks = {};
  int? _selectedAudioTrackId;

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  bool _isFullscreen = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    currentVideo = widget.video;
    _initializePlayer();
  }

  void _initializePlayer() {
    final streamUrl = currentVideo.getStreamUrl(language: _selectedLanguage);
    debugPrint('🎥 Inizializzazione VLC Player con URL: $streamUrl');

    _vlcPlayerController = VlcPlayerController.network(
      streamUrl,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([
          VlcAdvancedOptions.fileCaching(5000),
          VlcAdvancedOptions.networkCaching(5000),
        ]),
        http: VlcHttpOptions([
          VlcHttpOptions.httpUserAgent('VLC/3.0.0'),
        ]),
        subtitle: VlcSubtitleOptions([
          VlcSubtitleOptions.boldStyle(true),
          VlcSubtitleOptions.fontSize(30),
        ]),
      ),
    );

    _vlcPlayerController!.addListener(_onPlayerValueChanged);

    _vlcPlayerController!.addOnInitListener(() {
      debugPrint('✅ VLC Player inizializzato');
      _loadAudioTracks();
    });

    _startHideControlsTimer();
  }

  void _onPlayerValueChanged() {
    if (!mounted || _vlcPlayerController == null) return;

    final value = _vlcPlayerController!.value;
    setState(() {
      _isPlaying = value.isPlaying;
      _isBuffering = value.isBuffering;
      _position = value.position;
      _duration = value.duration;
    });
  }

  Future<void> _loadAudioTracks() async {
    if (_vlcPlayerController == null) return;
    try {
      final tracks = await _vlcPlayerController!.getAudioTracks();
      debugPrint('🔊 Tracce audio disponibili: ${tracks.length}');
      if (mounted) {
        setState(() {
          _availableAudioTracks = tracks;
          if (_selectedAudioTrackId == null && tracks.isNotEmpty) {
            _selectedAudioTrackId = tracks.keys.first;
          }
        });
        for (final entry in tracks.entries) {
          debugPrint('  └─ ${entry.value} (ID: ${entry.key})');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Errore nel caricamento tracce audio: $e');
    }
  }

  void _changeAudioTrack(int trackId) {
    debugPrint('🔊 Cambio traccia audio a: $trackId');
    _vlcPlayerController?.setAudioTrack(trackId);
    setState(() => _selectedAudioTrackId = trackId);
  }

  Future<void> _changeLanguage(String language) async {
    debugPrint('🌐 Cambio lingua a: ${language.toUpperCase()}');

    final newStreamUrl = currentVideo.getStreamUrl(language: language);
    setState(() {
      _selectedLanguage = language;
      _availableAudioTracks = {};
      _selectedAudioTrackId = null;
    });

    try {
      await _vlcPlayerController?.setMediaFromNetwork(
        newStreamUrl,
        autoPlay: true,
      );
      // Ricarica le tracce audio dopo un breve delay
      Future.delayed(const Duration(seconds: 2), _loadAudioTracks);
    } catch (e) {
      debugPrint('⚠️ Errore nel cambio lingua: $e');
    }
  }

  Future<void> _playNextEpisode() async {
    final nextUrl = currentVideo.getNextStreamUrl(language: _selectedLanguage);

    if (nextUrl != null) {
      debugPrint('▶️ Avvio episodio successivo: $nextUrl');

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
        _availableAudioTracks = {};
        _selectedAudioTrackId = null;
      });

      try {
        await _vlcPlayerController?.setMediaFromNetwork(
          nextUrl,
          autoPlay: true,
        );
        Future.delayed(const Duration(seconds: 2), _loadAudioTracks);
      } catch (e) {
        debugPrint('⚠️ Errore nel cambio episodio: $e');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun episodio successivo disponibile')),
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
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
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
    _vlcPlayerController?.removeListener(_onPlayerValueChanged);
    _vlcPlayerController?.dispose();
    // Ripristina orientamento
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

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
            // Video
            if (_vlcPlayerController != null)
              VlcPlayer(
                controller: _vlcPlayerController!,
                aspectRatio: 16 / 9,
                placeholder: Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.red),
                  ),
                ),
              ),
            // Buffering indicator
            if (_isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.red),
              ),
            // Overlay controlli
            if (_showControls)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
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

  // 🌐 SELEZIONE LINGUA
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

  // 🔊 SELEZIONE TRACCIA AUDIO
  Widget _buildAudioTrackSelector() {
    if (_availableAudioTracks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Traccia audio:',
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
              children: _availableAudioTracks.entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ElevatedButton(
                        onPressed: () => _changeAudioTrack(entry.key),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedAudioTrackId == entry.key
                              ? Colors.red
                              : Colors.grey[700],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          entry.value,
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

  // ⏭️ PROSSIMO EPISODIO
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

  // 🎮 OVERLAY CONTROLLI PLAYER
  Widget _buildPlayerControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color.fromRGBO(0, 0, 0, 0.6),
            const Color.fromRGBO(0, 0, 0, 0.0),
            const Color.fromRGBO(0, 0, 0, 0.0),
            const Color.fromRGBO(0, 0, 0, 0.7),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top bar - Titolo
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

          // Center - Play/Pause grande
          IconButton(
            iconSize: 64,
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white,
            ),
            onPressed: () {
              if (_isPlaying) {
                _vlcPlayerController?.pause();
              } else {
                _vlcPlayerController?.play();
              }
              _startHideControlsTimer();
            },
          ),

          // Bottom bar - Seek bar + controlli
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
                              ? _position.inMilliseconds
                                  .toDouble()
                                  .clamp(0.0, _duration.inMilliseconds.toDouble())
                              : 0.0,
                          min: 0.0,
                          max: _duration.inMilliseconds > 0
                              ? _duration.inMilliseconds.toDouble()
                              : 1.0,
                          onChanged: (value) {
                            _vlcPlayerController?.seekTo(
                              Duration(milliseconds: value.toInt()),
                            );
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
                      onPressed: () {
                        _vlcPlayerController?.setVolume(100);
                      },
                    ),

                    const Spacer(),

                    // Sottotitoli
                    IconButton(
                      icon: const Icon(Icons.subtitles, color: Colors.white),
                      onPressed: () => _showSubtitlesDialog(),
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

  void _showSubtitlesDialog() async {
    if (_vlcPlayerController == null) return;
    try {
      final spuTracks = await _vlcPlayerController!.getSpuTracks();
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Sottotitoli',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Disattiva', style: TextStyle(color: Colors.white)),
                onTap: () {
                  _vlcPlayerController?.setSpuTrack(-1);
                  Navigator.pop(context);
                },
              ),
              ...spuTracks.entries.map(
                (entry) => ListTile(
                  title: Text(entry.value, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    _vlcPlayerController?.setSpuTrack(entry.key);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Errore nel caricamento sottotitoli: $e');
    }
  }
}
