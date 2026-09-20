import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:onlystream/models/video_model.dart' as model;

// [Video_Player_Screen]
class VideoPlayerScreen extends StatefulWidget {
  final model.Video video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // [State_Variables]
  late model.Video currentVideo;

  late final Player _player;
  late final VideoController _videoController;

  final String _selectedLanguage = 'it';

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
          debugPrint('[StreamTracks] Audio tracks count: ${tracks.audio.length}');
          for (final t in tracks.audio) {
            debugPrint('[StreamTracks]   - ${t.title ?? t.language ?? t.id}');
          }
          debugPrint('[StreamTracks] Subtitle tracks count: ${tracks.subtitle.length}');
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
    final streamUrl = currentVideo.getStreamUrl(language: _selectedLanguage);
    debugPrint('[MediaStream] Opening M3U8/HLS stream');
    debugPrint('[MediaStream] URL: $streamUrl');

    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    _player.open(Media(streamUrl));
  }

  void _changeAudioTrack(AudioTrack track) {
    debugPrint('[AudioTrack] Changing audio track to: ${track.title ?? track.id}');
    _player.setAudioTrack(track);
  }

  void _playNextEpisode() {
    final nextUrl = currentVideo.getNextStreamUrl(language: _selectedLanguage);

    if (nextUrl != null) {
      debugPrint('[NextEpisode] Loading next episode: $nextUrl');

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
            content: Text('No next episode available'),
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
                        color: Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage.isNotEmpty
                            ? _errorMessage
                            : 'Error loading video stream',
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
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_hasError)
              Video(controller: _videoController, controls: NoVideoControls),
            if (!_hasError && _isBuffering)
              const Center(child: CircularProgressIndicator(color: Colors.red)),
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

          // [Center_Play_Pause_Button]
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

                    const Spacer(),

                    // [Next_Episode_Control]
                    if (currentVideo.type == "series" &&
                        currentVideo.nextEpisode != null &&
                        currentVideo.hasNext)
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        tooltip: 'Next Episode',
                        onPressed: _playNextEpisode,
                      ),

                    // [Audio_Track_Control]
                    IconButton(
                      icon: const Icon(Icons.audiotrack, color: Colors.white),
                      tooltip: 'Audio Track',
                      onPressed: _showAudioTracksDialog,
                    ),

                    // [Subtitles_Control]
                    IconButton(
                      icon: const Icon(Icons.subtitles, color: Colors.white),
                      tooltip: 'Subtitles',
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

  // [Audio_Tracks_Dialog]
  void _showAudioTracksDialog() {
    final tracks = _audioTracks
        .where((t) => t != AudioTrack.no() && t != AudioTrack.auto())
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Audio Track', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: tracks.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'No audio tracks available',
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
                          ? const Icon(Icons.check, color: Colors.red)
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
        backgroundColor: Colors.grey[900],
        title: const Text('Subtitles', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                'Disable',
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
