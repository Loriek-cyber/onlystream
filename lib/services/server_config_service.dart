import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ServerStatus {
  final bool isOnline;
  final String serviceName;
  final String version;
  final int latencyMs;
  final String? error;

  const ServerStatus({
    required this.isOnline,
    this.serviceName = 'easystreamapi',
    this.version = '',
    this.latencyMs = 0,
    this.error,
  });
}

class ServerPreset {
  final String name;
  final String url;

  const ServerPreset({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory ServerPreset.fromJson(Map<String, dynamic> json) => ServerPreset(
        name: json['name'] as String? ?? 'Server',
        url: json['url'] as String? ?? 'http://localhost:5555',
      );
}

/// Manages the main EasyStream API server IP/URL, language, quality preferences,
/// saved server presets, and live `/health` status checks.
class ServerConfigService extends ChangeNotifier {
  static final ServerConfigService instance = ServerConfigService._internal();

  ServerConfigService._internal();

  String _baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:5555',
  );
  String _defaultLanguage = 'it';
  String _preferredQuality = '1080p';
  String _preferredSource = 'auto';
  String _downloadDirectory = '';

  ServerStatus _status = const ServerStatus(isOnline: false);
  bool _isChecking = false;

  List<ServerPreset> _presets = [
    const ServerPreset(name: 'Locale (Default)', url: 'http://localhost:5555'),
    const ServerPreset(name: 'LAN Casa (192.168.1.100)', url: 'http://192.168.1.100:5555'),
    const ServerPreset(name: 'Android Emulator Host', url: 'http://10.0.2.2:5555'),
  ];

  String get baseUrl => _baseUrl.isEmpty ? 'http://localhost:5555' : _baseUrl;
  String get defaultLanguage => _defaultLanguage;
  String get preferredQuality => _preferredQuality;
  String get preferredSource => _preferredSource;
  String get downloadDirectory => _downloadDirectory;
  ServerStatus get status => _status;
  bool get isChecking => _isChecking;
  List<ServerPreset> get presets => List.unmodifiable(_presets);

  File get _configFile {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final dir = Directory('$home/.onlystream');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return File('${dir.path}/config.json');
  }

  Directory get effectiveDownloadDir {
    if (_downloadDirectory.isNotEmpty) {
      final custom = Directory(_downloadDirectory);
      if (custom.existsSync()) return custom;
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final dir = Directory('$home/Downloads/OnlyStream');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {
        return Directory.systemTemp;
      }
    }
    return dir;
  }

  Future<void> init() async {
    try {
      final file = _configFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        final savedUrl = data['base_url'] as String?;
        if (savedUrl != null && savedUrl.trim().isNotEmpty) {
          _baseUrl = _normalizeUrl(savedUrl);
        }
        _defaultLanguage = data['default_language'] as String? ?? 'it';
        _preferredQuality = data['preferred_quality'] as String? ?? '1080p';
        _preferredSource = data['preferred_source'] as String? ?? 'auto';
        _downloadDirectory = data['download_directory'] as String? ?? '';
        if (data['presets'] is List) {
          _presets = (data['presets'] as List)
              .map((e) => ServerPreset.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[ServerConfigService] Error loading config: $e');
    }
    if (_downloadDirectory.isEmpty) {
      _downloadDirectory = effectiveDownloadDir.path;
    }
    notifyListeners();
    unawaited(checkHealth());
  }

  Future<void> _save() async {
    try {
      final file = _configFile;
      final payload = {
        'base_url': _baseUrl,
        'default_language': _defaultLanguage,
        'preferred_quality': _preferredQuality,
        'preferred_source': _preferredSource,
        'download_directory': _downloadDirectory,
        'presets': _presets.map((p) => p.toJson()).toList(),
      };
      await file.writeAsString(json.encode(payload));
    } catch (e) {
      debugPrint('[ServerConfigService] Error saving config: $e');
    }
  }

  String _normalizeUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return 'http://localhost:5555';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    // If no port is specified and it's an IP or localhost without path, default to :5555
    final uri = Uri.tryParse(trimmed);
    if (uri != null && !uri.hasPort && (uri.host == 'localhost' || _looksLikeIp(uri.host))) {
      trimmed = '${uri.scheme}://${uri.host}:5555${uri.path}';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  bool _looksLikeIp(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) => int.tryParse(p) != null);
  }

  Future<ServerStatus> setServerUrl(String newUrl, {String? presetName}) async {
    _baseUrl = _normalizeUrl(newUrl);
    if (presetName != null && presetName.trim().isNotEmpty) {
      final existingIdx = _presets.indexWhere((p) => p.url == _baseUrl);
      if (existingIdx == -1) {
        _presets.add(ServerPreset(name: presetName.trim(), url: _baseUrl));
      }
    }
    await _save();
    notifyListeners();
    return checkHealth();
  }

  Future<void> addPreset(String name, String url) async {
    final normalized = _normalizeUrl(url);
    _presets.removeWhere((p) => p.url == normalized);
    _presets.add(ServerPreset(name: name.trim(), url: normalized));
    await _save();
    notifyListeners();
  }

  Future<void> removePreset(String url) async {
    _presets.removeWhere((p) => p.url == url);
    await _save();
    notifyListeners();
  }

  Future<void> setPreferences({
    String? language,
    String? quality,
    String? source,
    String? downloadDir,
  }) async {
    if (language != null) _defaultLanguage = language;
    if (quality != null) _preferredQuality = quality;
    if (source != null) _preferredSource = source;
    if (downloadDir != null) _downloadDirectory = downloadDir;
    await _save();
    notifyListeners();
  }

  /// Ping `GET /health` on the configured EasyStream API server.
  Future<ServerStatus> checkHealth({String? testUrl}) async {
    final targetBase = testUrl != null ? _normalizeUrl(testUrl) : baseUrl;
    if (testUrl == null) {
      _isChecking = true;
      notifyListeners();
    }

    final sw = Stopwatch()..start();
    try {
      final response = await http
          .get(Uri.parse('$targetBase/health'))
          .timeout(const Duration(seconds: 4));
      sw.stop();

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final result = ServerStatus(
          isOnline: data['status'] == 'ok',
          serviceName: data['service'] as String? ?? 'easystreamapi',
          version: data['version'] as String? ?? '1.0.0',
          latencyMs: sw.elapsedMilliseconds,
        );
        if (testUrl == null) {
          _status = result;
          _isChecking = false;
          notifyListeners();
        }
        return result;
      } else {
        final result = ServerStatus(
          isOnline: false,
          latencyMs: sw.elapsedMilliseconds,
          error: 'HTTP ${response.statusCode}',
        );
        if (testUrl == null) {
          _status = result;
          _isChecking = false;
          notifyListeners();
        }
        return result;
      }
    } catch (e) {
      sw.stop();
      final result = ServerStatus(
        isOnline: false,
        latencyMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
      if (testUrl == null) {
        _status = result;
        _isChecking = false;
        notifyListeners();
      }
      return result;
    }
  }
}
