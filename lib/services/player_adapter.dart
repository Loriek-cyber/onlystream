import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:onlystream/theme/app_theme.dart';

class PlayerTrackItem {
  final String id;
  final String title;
  final String? language;
  final String? uri;

  const PlayerTrackItem({
    required this.id,
    required this.title,
    this.language,
    this.uri,
  });

  bool get isExternal => uri != null && uri!.isNotEmpty;
}

/// Abstract media player interface so [VideoPlayerScreen] works identically
/// with `media_kit` in production and with deterministic fakes in widget tests.
abstract class PlayerAdapter {
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferStream;
  Stream<double> get volumeStream;
  Stream<double> get rateStream;
  Stream<bool> get completedStream;
  Stream<List<PlayerTrackItem>> get audioTracksStream;
  Stream<List<PlayerTrackItem>> get subtitleTracksStream;
  Stream<String?> get activeAudioIdStream;
  Stream<String?> get activeSubtitleIdStream;
  Stream<String> get errorStream;

  Future<void> open(
    String url, {
    Map<String, String>? httpHeaders,
    Duration start = Duration.zero,
  });

  Future<void> playOrPause();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setAudioTrack(PlayerTrackItem track);
  Future<void> setSubtitleTrack(PlayerTrackItem? track);
  Widget buildVideoView(BuildContext context, {BoxFit fit = BoxFit.contain});
  Future<void> dispose();
}

/// Production [PlayerAdapter] backed by `media_kit` + `media_kit_video`.
class MediaKitPlayerAdapter implements PlayerAdapter {
  MediaKitPlayerAdapter() {
    _player = Player();
    final useHwdec = !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
    _videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: useHwdec,
      ),
    );
  }

  late final Player _player;
  late final VideoController _videoController;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<Duration> get bufferStream => _player.stream.buffer;

  @override
  Stream<double> get volumeStream => _player.stream.volume;

  @override
  Stream<double> get rateStream => _player.stream.rate;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<List<PlayerTrackItem>> get audioTracksStream =>
      _player.stream.tracks.map(
        (tracks) => tracks.audio
            .where((t) => t != AudioTrack.no() && t != AudioTrack.auto())
            .map(
              (t) => PlayerTrackItem(
                id: t.id,
                title: t.title ?? t.language ?? 'Audio ${t.id}',
                language: t.language,
              ),
            )
            .toList(),
      );

  @override
  Stream<List<PlayerTrackItem>> get subtitleTracksStream =>
      _player.stream.tracks.map(
        (tracks) => tracks.subtitle
            .where((t) => t != SubtitleTrack.no() && t != SubtitleTrack.auto())
            .map(
              (t) => PlayerTrackItem(
                id: t.id,
                title: t.title ?? t.language ?? 'Sottotitoli ${t.id}',
                language: t.language,
              ),
            )
            .toList(),
      );

  @override
  Stream<String?> get activeAudioIdStream =>
      _player.stream.track.map((t) => t.audio.id);

  @override
  Stream<String?> get activeSubtitleIdStream =>
      _player.stream.track.map((t) => t.subtitle.id);

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Future<void> open(
    String url, {
    Map<String, String>? httpHeaders,
    Duration start = Duration.zero,
  }) {
    return _player.open(
      Media(
        url,
        httpHeaders:
            (httpHeaders != null && httpHeaders.isNotEmpty) ? httpHeaders : null,
        start: start > Duration.zero ? start : null,
      ),
    );
  }

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 100.0));

  @override
  Future<void> setRate(double rate) =>
      _player.setRate(rate.clamp(0.25, 4.0));

  @override
  Future<void> setAudioTrack(PlayerTrackItem track) {
    if (track.isExternal) {
      return _player.setAudioTrack(
        AudioTrack.uri(
          track.uri!,
          title: track.title,
          language: track.language,
        ),
      );
    }
    return _player.setAudioTrack(
      AudioTrack(track.id, track.title, track.language),
    );
  }

  @override
  Future<void> setSubtitleTrack(PlayerTrackItem? track) {
    if (track == null) {
      return _player.setSubtitleTrack(SubtitleTrack.no());
    }
    if (track.isExternal) {
      return _player.setSubtitleTrack(
        SubtitleTrack.uri(
          track.uri!,
          title: track.title,
          language: track.language,
        ),
      );
    }
    return _player.setSubtitleTrack(
      SubtitleTrack(track.id, track.title, track.language),
    );
  }

  @override
  Widget buildVideoView(BuildContext context, {BoxFit fit = BoxFit.contain}) {
    return Video(
      controller: _videoController,
      controls: NoVideoControls,
      fill: AppColors.background,
      fit: fit,
    );
  }

  @override
  Future<void> dispose() => _player.dispose();
}
