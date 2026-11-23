import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:onlystream/models/server.dart';
import 'package:path_provider/path_provider.dart';

export 'package:onlystream/models/server.dart';

const String _kEnvApiUrl = String.fromEnvironment('API_URL', defaultValue: '');

/// Bridge to the optional Android companion app (`com.loriek.easystreamserver`).
class CompanionServerBridge {
  CompanionServerBridge({
    MethodChannel? channel,
    this._isAndroidOverride,
  }) : _channel = channel ?? const MethodChannel('com.loriek.onlystream/companion');

  final MethodChannel _channel;
  final bool? _isAndroidOverride;

  bool get isSupported => _isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);

  Future<bool> isInstalled() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isInstalled');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startServer() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('startServer');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopServer() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('stopServer');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Manages server connection mode, remote URL/presets, playback defaults,
/// health checks, and Android-safe persistence via `path_provider`.
class ConfigService extends ChangeNotifier {
  static final ConfigService instance = ConfigService();

  static const String localServerUrl = 'http://127.0.0.1:5555';
  static const String defaultRemoteUrl = 'http://localhost:5555';

  static const Set<String> validServerModes = {'local', 'remote'};
  static const Set<String> validLanguages = {'it', 'en'};
  static const Set<String> validQualities = {'auto', '2160p', '1080p', '720p'};
  static const Set<String> validSources = {'auto', 'hls', 'torrent'};

  ConfigService({
    this._storageDirOverride,
    http.Client? httpClient,
    CompanionServerBridge? companionBridge,
    bool? isAndroidOverride,
    String? apiUrlEnvOverride,
    this.persist = true,
  })  : _httpClient = httpClient ?? http.Client(),
        _isAndroidOverride = isAndroidOverride,
        _apiUrlEnv = apiUrlEnvOverride ?? _kEnvApiUrl,
        companion = companionBridge ??
            CompanionServerBridge(isAndroidOverride: isAndroidOverride) {
    _applyDefaults();
  }

  final Directory? _storageDirOverride;
  final http.Client _httpClient;
  final bool? _isAndroidOverride;
  final String _apiUrlEnv;
  final CompanionServerBridge companion;
  final bool persist;

  late String _serverMode;
  late String _remoteUrl;
  String _language = 'it';
  String _quality = 'auto';
  String _source = 'auto';
  List<ServerPreset> _presets = _defaultPresets();

  HealthStatus _status = const HealthStatus(isOnline: false);
  bool _isChecking = false;
  bool _companionInstalled = false;
  bool _initialized = false;
  Directory? _resolvedStorageDir;

  bool get isAndroid => _isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
  String get serverMode => _serverMode;
  String get remoteUrl => _remoteUrl;
  String get baseUrl =>
      _serverMode == 'local' ? localServerUrl : normalizeUrl(_remoteUrl);
  String get language => _language;
  String get quality => _quality;
  String get source => _source;
  List<ServerPreset> get presets => List.unmodifiable(_presets);
  HealthStatus get status => _status;
  bool get isChecking => _isChecking;
  bool get companionInstalled => _companionInstalled;
  bool get initialized => _initialized;

  static List<ServerPreset> _defaultPresets() => const [
        ServerPreset(
          name: 'Locale (Desktop / Same Host)',
          url: 'http://localhost:5555',
        ),
        ServerPreset(
          name: 'PC / Docker LAN',
          url: 'http://192.168.1.100:5555',
        ),
        ServerPreset(
          name: 'Android Emulator Host',
          url: 'http://10.0.2.2:5555',
        ),
      ];

  void _applyDefaults() {
    final envUrl = _apiUrlEnv.trim();
    if (envUrl.isNotEmpty) {
      _serverMode = 'remote';
      _remoteUrl = normalizeUrl(envUrl);
    } else {
      _serverMode = isAndroid ? 'local' : 'remote';
      _remoteUrl = defaultRemoteUrl;
    }
  }

  static String normalizeUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return defaultRemoteUrl;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        !uri.hasPort &&
        (uri.host == 'localhost' || _looksLikeIpv4(uri.host))) {
      trimmed = '${uri.scheme}://${uri.host}:5555${uri.path}';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static bool _looksLikeIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) => int.tryParse(part) != null);
  }

  Future<Directory> resolveStorageDirectory() async {
    if (_storageDirOverride != null) {
      if (!await _storageDirOverride.exists()) {
        await _storageDirOverride.create(recursive: true);
      }
      return _storageDirOverride;
    }
    if (_resolvedStorageDir != null) return _resolvedStorageDir!;
    try {
      final dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _resolvedStorageDir = dir;
      return dir;
    } catch (_) {
      final fallback = Directory.systemTemp;
      _resolvedStorageDir = fallback;
      return fallback;
    }
  }

  Future<File> _configFile() async {
    final dir = await resolveStorageDirectory();
    return File('${dir.path}/config.json');
  }

  Future<void> init({bool checkHealthOnInit = true}) async {
    _applyDefaults();
    if (persist) {
      try {
        final file = await _configFile();
        if (await file.exists()) {
          final raw = await file.readAsString();
          final data = json.decode(raw);
          if (data is Map<String, dynamic>) {
            final mode = data['server_mode']?.toString();
            if (mode != null && validServerModes.contains(mode)) {
              _serverMode = mode;
            }
            final savedRemote = data['remote_url']?.toString();
            if (savedRemote != null && savedRemote.trim().isNotEmpty) {
              _remoteUrl = normalizeUrl(savedRemote);
            }
            final lang = data['language']?.toString();
            if (lang != null && validLanguages.contains(lang)) {
              _language = lang;
            }
            final qual = data['quality']?.toString();
            if (qual != null && validQualities.contains(qual)) {
              _quality = qual;
            }
            final src = data['source']?.toString();
            if (src != null && validSources.contains(src)) {
              _source = src;
            }
            if (data['presets'] is List) {
              final loaded = (data['presets'] as List)
                  .whereType<Map<String, dynamic>>()
                  .map(ServerPreset.fromJson)
                  .toList();
              if (loaded.isNotEmpty) {
                _presets = loaded;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[ConfigService] Failed to read config: $e');
      }
    }

    _companionInstalled = await companion.isInstalled();
    _initialized = true;
    notifyListeners();

    if (checkHealthOnInit) {
      unawaited(checkHealth());
    }
  }

  Future<void> _save() async {
    if (!persist) return;
    try {
      final file = await _configFile();
      final payload = {
        'server_mode': _serverMode,
        'remote_url': _remoteUrl,
        'language': _language,
        'quality': _quality,
        'source': _source,
        'presets': _presets.map((p) => p.toJson()).toList(),
      };
      await file.writeAsString(json.encode(payload));
    } catch (e) {
      debugPrint('[ConfigService] Failed to save config: $e');
    }
  }

  Future<void> refreshCompanionStatus() async {
    final installed = await companion.isInstalled();
    if (installed != _companionInstalled) {
      _companionInstalled = installed;
      notifyListeners();
    }
  }

  Future<bool> startLocalServer() async {
    final ok = await companion.startServer();
    if (ok) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await checkHealth();
    }
    return ok;
  }

  Future<bool> stopLocalServer() async {
    final ok = await companion.stopServer();
    await checkHealth();
    return ok;
  }

  Future<HealthStatus> setServerMode(String mode) async {
    if (!validServerModes.contains(mode)) return _status;
    _serverMode = mode;
    await _save();
    notifyListeners();
    return checkHealth();
  }

  Future<HealthStatus> setRemoteUrl(
    String url, {
    String? presetName,
    bool switchToRemote = true,
  }) async {
    _remoteUrl = normalizeUrl(url);
    if (switchToRemote) {
      _serverMode = 'remote';
    }
    if (presetName != null && presetName.trim().isNotEmpty) {
      final exists = _presets.any((p) => p.url == _remoteUrl);
      if (!exists) {
        _presets = [
          ..._presets,
          ServerPreset(name: presetName.trim(), url: _remoteUrl),
        ];
      }
    }
    await _save();
    notifyListeners();
    return checkHealth();
  }

  Future<void> addPreset(String name, String url) async {
    final normalized = normalizeUrl(url);
    final cleanedName = name.trim().isEmpty ? normalized : name.trim();
    _presets = [
      ..._presets.where((p) => p.url != normalized),
      ServerPreset(name: cleanedName, url: normalized),
    ];
    await _save();
    notifyListeners();
  }

  Future<void> removePreset(String url) async {
    _presets = _presets.where((p) => p.url != url).toList();
    await _save();
    notifyListeners();
  }

  Future<void> setPreferences({
    String? language,
    String? quality,
    String? source,
  }) async {
    if (language != null && validLanguages.contains(language)) {
      _language = language;
    }
    if (quality != null && validQualities.contains(quality)) {
      _quality = quality;
    }
    if (source != null && validSources.contains(source)) {
      _source = source;
    }
    await _save();
    notifyListeners();
  }

  Future<HealthStatus> checkHealth({String? testUrl}) async {
    final targetBase =
        testUrl != null ? normalizeUrl(testUrl) : baseUrl;
    if (testUrl == null) {
      _isChecking = true;
      notifyListeners();
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _httpClient
          .get(Uri.parse('$targetBase/health'))
          .timeout(const Duration(seconds: 4));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final status = decoded is Map<String, dynamic>
            ? HealthStatus.fromJson(
                decoded,
                latencyMs: stopwatch.elapsedMilliseconds,
              )
            : HealthStatus(
                isOnline: false,
                latencyMs: stopwatch.elapsedMilliseconds,
                error: 'Risposta non valida',
              );
        if (testUrl == null) {
          _status = status;
          _isChecking = false;
          notifyListeners();
        }
        return status;
      }

      final fail = HealthStatus(
        isOnline: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: 'HTTP ${response.statusCode}',
      );
      if (testUrl == null) {
        _status = fail;
        _isChecking = false;
        notifyListeners();
      }
      return fail;
    } catch (e) {
      stopwatch.stop();
      final fail = HealthStatus(
        isOnline: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
      if (testUrl == null) {
        _status = fail;
        _isChecking = false;
        notifyListeners();
      }
      return fail;
    }
  }
}
