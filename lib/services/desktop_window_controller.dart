import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum WindowResizeEdge {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Coordinates native Linux (GTK) and Windows (Win32/DWM) custom window frame
/// actions and window state synchronization over `com.loriek.onlystream/window`.
class DesktopWindowController extends ChangeNotifier {
  static final DesktopWindowController instance = DesktopWindowController();

  DesktopWindowController({
    MethodChannel? channel,
    this.isSupportedOverride,
  }) : _channel =
            channel ?? const MethodChannel('com.loriek.onlystream/window');

  final MethodChannel _channel;
  final bool? isSupportedOverride;

  bool _isMaximized = false;
  bool _isFullscreen = false;
  bool _isFocused = true;
  bool _initialized = false;

  bool get isSupported =>
      isSupportedOverride ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.windows));

  bool get isMaximized => _isMaximized;
  bool get isFullscreen => _isFullscreen;
  bool get isFocused => _isFocused;
  bool get showTitleBar => isSupported && !_isFullscreen;

  Future<void> init() async {
    if (!isSupported) return;
    _channel.setMethodCallHandler(_handleMethodCall);
    _initialized = true;
    try {
      final result = await _channel.invokeMethod<dynamic>('getWindowState');
      _applyState(result);
    } on MissingPluginException {
      // Ignored in tests or unsupported runners.
    } on PlatformException {
      // Ignored if native channel is unavailable.
    } catch (_) {
      // Ignored.
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onWindowStateChanged') {
      _applyState(call.arguments);
    }
    return null;
  }

  void _applyState(dynamic raw) {
    if (raw is! Map) return;
    final nextMaximized = raw['isMaximized'] is bool
        ? raw['isMaximized'] as bool
        : _isMaximized;
    final nextFullscreen = raw['isFullscreen'] is bool
        ? raw['isFullscreen'] as bool
        : _isFullscreen;
    final nextFocused =
        raw['isFocused'] is bool ? raw['isFocused'] as bool : _isFocused;

    if (nextMaximized != _isMaximized ||
        nextFullscreen != _isFullscreen ||
        nextFocused != _isFocused) {
      _isMaximized = nextMaximized;
      _isFullscreen = nextFullscreen;
      _isFocused = nextFocused;
      notifyListeners();
    }
  }

  Future<void> _invoke(String method, [dynamic arguments]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Ignored in tests or unsupported runners.
    } on PlatformException {
      // Ignored.
    } catch (_) {
      // Ignored.
    }
  }

  Future<void> minimize() => _invoke('minimize');

  Future<void> maximize() async {
    if (!isSupported) return;
    if (!_isMaximized || _isFullscreen) {
      _isMaximized = true;
      _isFullscreen = false;
      notifyListeners();
    }
    await _invoke('maximize');
  }

  Future<void> unmaximize() async {
    if (!isSupported) return;
    if (_isMaximized || _isFullscreen) {
      _isMaximized = false;
      _isFullscreen = false;
      notifyListeners();
    }
    await _invoke('unmaximize');
  }

  Future<void> toggleMaximize() =>
      _isMaximized ? unmaximize() : maximize();

  Future<void> setFullscreen(bool fullscreen) async {
    if (!isSupported) return;
    if (_isFullscreen != fullscreen) {
      _isFullscreen = fullscreen;
      notifyListeners();
    }
    await _invoke('setFullscreen', fullscreen);
  }

  Future<void> toggleFullscreen() => setFullscreen(!_isFullscreen);

  Future<void> close() => _invoke('close');

  Future<void> startDragging() => _invoke('startDragging');

  Future<void> startResizing(WindowResizeEdge edge) =>
      _invoke('startResizing', edge.name);

  @override
  void dispose() {
    if (_initialized) {
      _channel.setMethodCallHandler(null);
      _initialized = false;
    }
    super.dispose();
  }
}
