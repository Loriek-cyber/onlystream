import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cast_server.dart';
import 'code_util.dart';
import 'dlna_service.dart';

/// Playback state reported by the active Cast receiver (Web Receiver or DLNA).
enum CastPlaybackState {
  idle,
  buffering,
  playing,
  paused,
  ended,
  error,
}

/// Active Cast transport target.
enum CastTargetType {
  none,
  webReceiver,
  dlna,
}

/// Periodic playback position update emitted on [CastController.positionStream]
/// so the host player can persist watch progress continuously while casting.
class CastPositionUpdate {
  const CastPositionUpdate({
    required this.position,
    required this.duration,
    required this.state,
  });

  final Duration position;
  final Duration duration;
  final CastPlaybackState state;
}

/// Coordinates local Cast HTTP proxying, Web Video Caster-style Web Receiver
/// sessions, and UPnP / DLNA MediaRenderer sessions.
class CastController extends ChangeNotifier {
  CastController({
    CastServer? server,
    DlnaService? dlnaService,
  })  : _server = server ?? CastServer(),
        _dlnaService = dlnaService ?? DlnaService() {
    _wireServerCallbacks();
  }

  /// Shared app-wide singleton instance.
  static final CastController instance = CastController();

  final CastServer _server;
  final DlnaService _dlnaService;

  final StreamController<CastPositionUpdate> _positionController =
      StreamController<CastPositionUpdate>.broadcast();

  CastTargetType _targetType = CastTargetType.none;
  DlnaDevice? _activeDlnaDevice;
  List<DlnaDevice> _dlnaDevices = const [];
  bool _isDiscoveringDlna = false;
  bool _isWebReceiverConnected = false;
  bool _isCasting = false;

  String? _activeTitle;
  String? _lastError;
  CastPlaybackState _playbackState = CastPlaybackState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  Map<String, dynamic>? _pendingWebLoadCommand;
  Timer? _dlnaPollTimer;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Public state getters
  // ---------------------------------------------------------------------------

  bool get isServerRunning => _server.isRunning;

  /// Whether a media item is actively being cast to a Web Receiver or DLNA TV.
  bool get isCasting => _isCasting;

  /// Whether a receiver (Web Receiver browser tab or DLNA TV) is connected.
  bool get isConnected =>
      _isWebReceiverConnected ||
      (_targetType == CastTargetType.dlna && _activeDlnaDevice != null);

  bool get isWebReceiverConnected => _isWebReceiverConnected;

  CastTargetType get targetType => _targetType;

  String? get activeTargetName {
    if (_targetType == CastTargetType.dlna && _activeDlnaDevice != null) {
      return _activeDlnaDevice!.friendlyName;
    }
    if (_targetType == CastTargetType.webReceiver || _isWebReceiverConnected) {
      return 'Web Receiver';
    }
    return null;
  }

  String? get activeTitle => _activeTitle;

  /// Base36 pairing code derived from the local LAN IPv4 address (e.g. `8I`).
  String? get pairingCode =>
      _server.isRunning ? CodeUtil.ipToCode(_server.host) : null;

  /// Base36 port code when the server is bound to a non-default port.
  String? get portCode {
    if (!_server.isRunning || _server.port == CodeUtil.defaultPort) return null;
    return CodeUtil.portToCode(_server.port);
  }

  /// Full LAN URL to open on a Smart TV or desktop browser.
  String? get receiverUrl => _server.isRunning ? _server.webReceiverUrl : null;

  CastPlaybackState get playbackState => _playbackState;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  String? get lastError => _lastError;

  bool get isDiscoveringDlna => _isDiscoveringDlna;
  List<DlnaDevice> get dlnaDevices => List.unmodifiable(_dlnaDevices);
  DlnaDevice? get activeDlnaDevice => _activeDlnaDevice;

  /// Broadcast stream of position/duration telemetry updates from both Web
  /// Receiver (`/web-receiver-io/position`) and DLNA (`GetPositionInfo` every 2s).
  Stream<CastPositionUpdate> get positionStream => _positionController.stream;

  // ---------------------------------------------------------------------------
  // Server lifecycle & DLNA discovery
  // ---------------------------------------------------------------------------

  /// Starts the local [CastServer] if not already running and binds telemetry
  /// listeners.
  Future<void> startServer({String? advertiseHost}) async {
    _wireServerCallbacks();
    if (_server.isRunning) return;

    await _server.start(advertiseHost: advertiseHost);
    _safeNotify();
  }

  void _wireServerCallbacks() {
    _server.onReceiverConnectionChanged = (connected, _) {
      _isWebReceiverConnected = connected;
      if (connected && _pendingWebLoadCommand != null) {
        final cmd = _pendingWebLoadCommand!;
        _pendingWebLoadCommand = null;
        _server.enqueueCommand(cmd);
      }
      if (!connected && _targetType == CastTargetType.webReceiver) {
        _isCasting = false;
        _playbackState = CastPlaybackState.idle;
      }
      _safeNotify();
    };

    _server.onStateTelemetry = (rawState) {
      _playbackState = _parsePlaybackState(rawState);
      if (_playbackState == CastPlaybackState.ended) {
        _emitPosition();
      }
      _safeNotify();
    };

    _server.onPositionTelemetry = (pos, dur) {
      _position = pos;
      if (dur > Duration.zero) {
        _duration = dur;
      }
      _emitPosition();
      _safeNotify();
    };

    _server.onVolumeTelemetry = (vol, muted) {
      _volume = muted ? 0.0 : vol.clamp(0.0, 1.0);
      _safeNotify();
    };

    _server.onErrorTelemetry = (msg) {
      _lastError = msg;
      _playbackState = CastPlaybackState.error;
      _safeNotify();
    };

    _server.onDisconnectTelemetry = () {
      _isWebReceiverConnected = false;
      if (_targetType == CastTargetType.webReceiver) {
        _isCasting = false;
        _targetType = CastTargetType.none;
        _playbackState = CastPlaybackState.idle;
      }
      _safeNotify();
    };
  }

  /// Stops the local Cast HTTP server and ends any active Cast session.
  Future<void> stopServer() async {
    await disconnect();
    await _server.stop();
    _isWebReceiverConnected = false;
    _safeNotify();
  }

  /// Discovers DLNA / UPnP MediaRenderer devices on the local LAN.
  Future<List<DlnaDevice>> discoverDlna({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_isDiscoveringDlna) return _dlnaDevices;

    _isDiscoveringDlna = true;
    _safeNotify();
    try {
      _dlnaDevices = await _dlnaService.discover(timeout: timeout);
      return _dlnaDevices;
    } finally {
      _isDiscoveringDlna = false;
      _safeNotify();
    }
  }

  // ---------------------------------------------------------------------------
  // Casting & remote transport controls
  // ---------------------------------------------------------------------------

  /// Casts [url] to either [dlnaDevice] (if provided) or the connected Web
  /// Receiver, automatically routing through the local [CastServer] proxy,
  /// HLS M3U8 rewriter, and SRT->WebVTT subtitle converter.
  Future<void> castMedia({
    required String url,
    required String title,
    Map<String, String>? headers,
    String? subtitleUrl,
    String? posterUrl,
    Duration initialPosition = Duration.zero,
    bool isHls = false,
    DlnaDevice? dlnaDevice,
  }) async {
    await startServer();
    _stopDlnaPolling();

    final effectiveHeaders = headers ?? const <String, String>{};
    final effectiveIsHls =
        isHls || url.toLowerCase().contains('.m3u8');

    final proxiedMediaUrl = effectiveIsHls
        ? _server.buildM3u8Url(url, headers: effectiveHeaders)
        : _server.buildProxyUrl(url, headers: effectiveHeaders);

    final proxiedSubtitleUrl =
        (subtitleUrl != null && subtitleUrl.trim().isNotEmpty)
            ? _server.buildSubtitleUrl(subtitleUrl, headers: effectiveHeaders)
            : null;

    _activeTitle = title;
    _lastError = null;
    _position = initialPosition;
    _duration = Duration.zero;
    _playbackState = CastPlaybackState.buffering;

    if (dlnaDevice != null) {
      _targetType = CastTargetType.dlna;
      _activeDlnaDevice = dlnaDevice;
      _isCasting = true;
      _pendingWebLoadCommand = null;
      _safeNotify();

      try {
        final mimeType =
            effectiveIsHls ? 'application/vnd.apple.mpegurl' : 'video/mp4';
        await _dlnaService.setAvTransportUri(
          dlnaDevice,
          mediaUrl: proxiedMediaUrl,
          title: title,
          mimeType: mimeType,
          subtitleUrl: proxiedSubtitleUrl,
          posterUrl: posterUrl,
        );
        await _dlnaService.play(dlnaDevice);
        if (initialPosition > Duration.zero) {
          await _dlnaService.seek(dlnaDevice, initialPosition);
        }
        _playbackState = CastPlaybackState.playing;
        _startDlnaPolling(dlnaDevice);
      } catch (e) {
        _lastError = e.toString();
        _playbackState = CastPlaybackState.error;
        _isCasting = false;
      }
      _safeNotify();
      return;
    }

    // Web Receiver target
    _targetType = CastTargetType.webReceiver;
    _activeDlnaDevice = null;
    _isCasting = true;

    final loadCmd = <String, dynamic>{
      'type': 'loadMedia',
      'url': proxiedMediaUrl,
      'title': title,
      'isHls': effectiveIsHls,
      'position': initialPosition.inSeconds,
      'subtitleUrl': ?proxiedSubtitleUrl,
      if (posterUrl != null && posterUrl.isNotEmpty) 'posterUrl': posterUrl,
    };

    if (_server.hasConnectedReceiver) {
      _pendingWebLoadCommand = null;
      _server.enqueueCommand(loadCmd);
    } else {
      // Queue both in server command queue and pending slot so as soon as the
      // TV browser opens the receiver URL it immediately starts playback.
      _pendingWebLoadCommand = loadCmd;
    }
    _safeNotify();
  }

  /// Resumes playback on the active receiver.
  Future<void> play() async {
    if (_targetType == CastTargetType.dlna && _activeDlnaDevice != null) {
      await _dlnaService.play(_activeDlnaDevice!);
      _playbackState = CastPlaybackState.playing;
      _safeNotify();
    } else if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({'type': 'play'});
      _playbackState = CastPlaybackState.playing;
      _safeNotify();
    }
  }

  /// Pauses playback on the active receiver.
  Future<void> pause() async {
    if (_targetType == CastTargetType.dlna && _activeDlnaDevice != null) {
      await _dlnaService.pause(_activeDlnaDevice!);
      _playbackState = CastPlaybackState.paused;
      _safeNotify();
    } else if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({'type': 'pause'});
      _playbackState = CastPlaybackState.paused;
      _safeNotify();
    }
  }

  /// Stops playback on the active receiver without tearing down the local server.
  Future<void> stop() async {
    _stopDlnaPolling();
    if (_targetType == CastTargetType.dlna && _activeDlnaDevice != null) {
      try {
        await _dlnaService.stop(_activeDlnaDevice!);
      } catch (_) {}
    } else if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({'type': 'stop'});
    }
    _isCasting = false;
    _playbackState = CastPlaybackState.idle;
    _safeNotify();
  }

  /// Seeks to [position] on the active receiver.
  Future<void> seek(Duration position) async {
    final safePos = position.isNegative ? Duration.zero : position;
    _position = safePos;
    _safeNotify();

    if (_targetType == CastTargetType.dlna && _activeDlnaDevice != null) {
      await _dlnaService.seek(_activeDlnaDevice!, safePos);
      _emitPosition();
    } else if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({
        'type': 'setPosition',
        'position': safePos.inMilliseconds / 1000.0,
      });
      _emitPosition();
    }
  }

  /// Sets receiver volume (`0.0` .. `1.0`).
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    _volume = clamped;
    _safeNotify();

    if (_targetType == CastTargetType.dlna && _activeDlnaDevice != null) {
      await _dlnaService.setVolume(_activeDlnaDevice!, (clamped * 100).round());
    } else if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({'type': 'setVolume', 'volume': clamped});
    }
  }

  /// Sets playback speed on the Web Receiver.
  Future<void> setSpeed(double speed) async {
    if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({'type': 'setSpeed', 'speed': speed});
    }
  }

  /// Sets video fit mode (`'contain'` or `'cover'`) on the Web Receiver.
  Future<void> setZoom(String mode) async {
    if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({'type': 'zoom', 'mode': mode});
    }
  }

  /// Disconnects from the active Cast session (DLNA or Web Receiver).
  Future<void> disconnect() async {
    _stopDlnaPolling();
    _pendingWebLoadCommand = null;

    if (_targetType == CastTargetType.dlna && _activeDlnaDevice != null) {
      try {
        await _dlnaService.stop(_activeDlnaDevice!);
      } catch (_) {}
    } else if (_targetType == CastTargetType.webReceiver) {
      _server.enqueueCommand({'type': 'disconnect'});
    }

    _activeDlnaDevice = null;
    _targetType = CastTargetType.none;
    _isCasting = false;
    _activeTitle = null;
    _playbackState = CastPlaybackState.idle;
    _lastError = null;
    _safeNotify();
  }

  void _startDlnaPolling(DlnaDevice device) {
    _stopDlnaPolling();
    _dlnaPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_targetType != CastTargetType.dlna || _activeDlnaDevice != device) {
        _stopDlnaPolling();
        return;
      }
      final info = await _dlnaService.getPositionInfo(device);
      if (info == null || _disposed) return;

      _position = info.position;
      if (info.duration > Duration.zero) {
        _duration = info.duration;
      }
      _emitPosition();
      _safeNotify();
    });
  }

  void _stopDlnaPolling() {
    _dlnaPollTimer?.cancel();
    _dlnaPollTimer = null;
  }

  void _emitPosition() {
    if (_positionController.isClosed) return;
    _positionController.add(
      CastPositionUpdate(
        position: _position,
        duration: _duration,
        state: _playbackState,
      ),
    );
  }

  CastPlaybackState _parsePlaybackState(String raw) {
    switch (raw.toLowerCase()) {
      case 'playing':
        return CastPlaybackState.playing;
      case 'paused':
        return CastPlaybackState.paused;
      case 'buffering':
        return CastPlaybackState.buffering;
      case 'ended':
        return CastPlaybackState.ended;
      case 'error':
        return CastPlaybackState.error;
      default:
        return CastPlaybackState.idle;
    }
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopDlnaPolling();
    _positionController.close();
    _dlnaService.dispose();
    _server.dispose();
    super.dispose();
  }
}
