import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'code_util.dart';

/// Top-level helper to rewrite an HLS M3U8 manifest so that:
/// - Sub-playlists (`.m3u8` or entries following `#EXT-X-STREAM-INF`) point to
///   [m3u8UrlBuilder]
/// - Media segments (`.ts`, `.m4s`, etc.) point to [proxyUrlBuilder]
/// - `URI="..."` attributes in `#EXT-X-KEY`, `#EXT-X-MAP`, `#EXT-X-MEDIA`,
///   `#EXT-X-I-FRAME-STREAM-INF` (and any other `#EXT-X-` tag) are resolved
///   against [baseUri] and rewritten through [m3u8UrlBuilder] or
///   [proxyUrlBuilder].
String rewriteM3U8(
  String content,
  Uri baseUri, {
  required String Function(String resolvedUrl) proxyUrlBuilder,
  required String Function(String resolvedUrl) m3u8UrlBuilder,
}) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final out = <String>[];

  var nextUriIsPlaylist = false;
  final uriAttrRegex = RegExp(r'URI="([^"]+)"');

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      out.add(line);
      continue;
    }

    if (trimmed.startsWith('#')) {
      if (trimmed.startsWith('#EXT-X-STREAM-INF')) {
        nextUriIsPlaylist = true;
      }

      if (trimmed.contains('URI="')) {
        final isPlaylistTag = trimmed.startsWith('#EXT-X-MEDIA') ||
            trimmed.startsWith('#EXT-X-I-FRAME-STREAM-INF');
        final rewrittenLine = line.replaceAllMapped(uriAttrRegex, (match) {
          final rawUri = match.group(1)!;
          final resolved = baseUri.resolve(rawUri).toString();
          final isM3u8 = isPlaylistTag || _looksLikeM3u8(resolved);
          final target =
              isM3u8 ? m3u8UrlBuilder(resolved) : proxyUrlBuilder(resolved);
          return 'URI="$target"';
        });
        out.add(rewrittenLine);
      } else {
        out.add(line);
      }
      continue;
    }

    final resolved = baseUri.resolve(trimmed).toString();
    final isPlaylist = nextUriIsPlaylist || _looksLikeM3u8(resolved);
    nextUriIsPlaylist = false;
    out.add(isPlaylist ? m3u8UrlBuilder(resolved) : proxyUrlBuilder(resolved));
  }

  return out.join('\n');
}

bool _looksLikeM3u8(String url) {
  final parsed = Uri.tryParse(url);
  final path = (parsed?.path ?? url).toLowerCase();
  return path.endsWith('.m3u8') || path.endsWith('.m3u');
}

/// Converts an SRT subtitle string into a valid WebVTT (`text/vtt`) string.
///
/// Strips UTF-8 BOM, normalizes line endings to `\n`, converts SRT comma
/// milliseconds (`00:01:23,456`) to WebVTT dot milliseconds (`00:01:23.456`),
/// and prepends `WEBVTT\n\n` if not already present.
String srtToVtt(String input) {
  var text = input;
  if (text.startsWith('\uFEFF')) {
    text = text.substring(1);
  }
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final trimmedStart = text.trimLeft();
  if (trimmedStart.startsWith('WEBVTT')) {
    return trimmedStart;
  }

  final timestampRegex = RegExp(r'(\d{1,2}:\d{2}:\d{2}),(\d{3})');
  final converted = text.replaceAllMapped(
    timestampRegex,
    (m) => '${m.group(1)}.${m.group(2)}',
  );

  return 'WEBVTT\n\n${converted.trimLeft()}';
}

class _ProxyEntry {
  const _ProxyEntry({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String> headers;
}

/// Local HTTP Cast Server implementing:
/// - `/proxy?id=<token>` (header injection, `Range` / `206`, up to 5 redirects, CORS)
/// - `/m3u8?id=<token>` (HLS manifest fetcher & rewriter)
/// - `/subtitle?id=<token>` (SRT -> WebVTT converter)
/// - `/web-receiver/discover.gif` (1x1 transparent GIF for LAN probing)
/// - `/web-receiver/` (minimal monochrome dark HTML5 + hls.js Web Receiver)
/// - `/web-receiver-io/longPoll` (single-client long-polling with `409 Busy` & 25s heartbeat)
/// - `/web-receiver-io/{state,position,volume,error,disconnect}` (telemetry POSTs)
class CastServer {
  CastServer({
    this.preferredPort = CodeUtil.defaultPort,
    this.heartbeatDuration = const Duration(seconds: 25),
    this.clientStaleDuration = const Duration(seconds: 35),
    this.maxRedirects = 5,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const int _maxTokens = 2000;

  /// Standard 43-byte 1x1 transparent GIF.
  static final Uint8List _transparentGif = Uint8List.fromList(const [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
    0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
  ]);

  final int preferredPort;
  final Duration heartbeatDuration;
  final Duration clientStaleDuration;
  final int maxRedirects;
  final HttpClient _httpClient;

  HttpServer? _server;
  String _host = '127.0.0.1';

  final Map<String, _ProxyEntry> _tokens = <String, _ProxyEntry>{};
  final Map<String, String> _dedupKeys = <String, String>{};
  final Random _random = Random.secure();

  // Single-client long-poll state
  String? _activeClientId;
  DateTime? _lastClientActivity;
  Completer<List<Map<String, dynamic>>>? _pendingPoll;
  Timer? _heartbeatTimer;
  final List<Map<String, dynamic>> _commandQueue = <Map<String, dynamic>>[];

  // Telemetry callbacks
  void Function(bool connected, String? clientId)? onReceiverConnectionChanged;
  void Function(String state)? onStateTelemetry;
  void Function(Duration position, Duration duration)? onPositionTelemetry;
  void Function(double volume, bool muted)? onVolumeTelemetry;
  void Function(String message)? onErrorTelemetry;
  void Function()? onDisconnectTelemetry;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  String get host => _host;
  String? get activeClientId => _activeClientId;
  bool get hasConnectedReceiver => _isActiveClientAlive();

  /// Base origin URL (`http://<host>:<port>`).
  String get baseUrl => 'http://$_host:$port';

  /// Full Web Receiver URL (`http://<host>:<port>/web-receiver/`).
  String get webReceiverUrl => '$baseUrl/web-receiver/';

  /// Starts the HTTP server on [preferredPort] (falling back to port `0` if
  /// busy) bound to [InternetAddress.anyIPv4].
  Future<void> start({String? advertiseHost}) async {
    if (_server != null) return;

    _host = advertiseHost ?? (await CodeUtil.detectLanIpv4()) ?? '127.0.0.1';

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }

    _server!.listen(
      _handleRequest,
      onError: (_) {},
      cancelOnError: false,
    );
  }

  /// Stops the HTTP server and cleans up pending long-poll connections.
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_pendingPoll != null && !_pendingPoll!.isCompleted) {
      _pendingPoll!.complete(const []);
    }
    _pendingPoll = null;
    _activeClientId = null;
    _lastClientActivity = null;
    _commandQueue.clear();
    _tokens.clear();
    _dedupKeys.clear();

    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// Releases the HTTP client as well as stopping the server.
  Future<void> dispose() async {
    await stop();
    _httpClient.close(force: true);
  }

  /// Registers [url] + [headers] and returns a short opaque token.
  String registerUrl(String url, {Map<String, String> headers = const {}}) {
    final sortedKeys = headers.keys.toList()..sort();
    final dedupKey = '$url|${sortedKeys.map((k) => '$k=${headers[k]}').join('&')}';
    final existing = _dedupKeys[dedupKey];
    if (existing != null && _tokens.containsKey(existing)) {
      return existing;
    }

    if (_tokens.length >= _maxTokens) {
      final oldestKey = _tokens.keys.first;
      _tokens.remove(oldestKey);
      _dedupKeys.removeWhere((_, v) => v == oldestKey);
    }

    final token = _generateToken();
    _tokens[token] = _ProxyEntry(
      url: url,
      headers: Map<String, String>.unmodifiable(headers),
    );
    _dedupKeys[dedupKey] = token;
    return token;
  }

  /// Registers [targetUrl] and returns the local `/proxy?id=<token>` URL.
  String buildProxyUrl(
    String targetUrl, {
    Map<String, String> headers = const {},
  }) {
    final token = registerUrl(targetUrl, headers: headers);
    return '$baseUrl/proxy?id=$token';
  }

  /// Registers [targetUrl] and returns the local `/m3u8?id=<token>` URL.
  String buildM3u8Url(
    String targetUrl, {
    Map<String, String> headers = const {},
  }) {
    final token = registerUrl(targetUrl, headers: headers);
    return '$baseUrl/m3u8?id=$token';
  }

  /// Registers [targetUrl] and returns the local `/subtitle?id=<token>` URL.
  String buildSubtitleUrl(
    String targetUrl, {
    Map<String, String> headers = const {},
  }) {
    final token = registerUrl(targetUrl, headers: headers);
    return '$baseUrl/subtitle?id=$token';
  }

  /// Enqueues a JSON command for the connected Web Receiver.
  ///
  /// If a long-poll request is currently waiting, delivers immediately.
  void enqueueCommand(Map<String, dynamic> command) {
    if (_pendingPoll != null && !_pendingPoll!.isCompleted) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      final completer = _pendingPoll!;
      _pendingPoll = null;
      completer.complete([command]);
    } else {
      _commandQueue.add(command);
    }
  }

  /// Clears the active Web Receiver session so another client may connect.
  void clearActiveReceiver() {
    final prev = _activeClientId;
    _activeClientId = null;
    _lastClientActivity = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_pendingPoll != null && !_pendingPoll!.isCompleted) {
      _pendingPoll!.complete(const []);
    }
    _pendingPoll = null;
    _commandQueue.clear();
    if (prev != null) {
      onReceiverConnectionChanged?.call(false, prev);
    }
  }

  String _generateToken() {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  bool _isActiveClientAlive() {
    if (_activeClientId == null) return false;
    if (_pendingPoll != null && !_pendingPoll!.isCompleted) return true;
    final last = _lastClientActivity;
    if (last == null) return false;
    return DateTime.now().difference(last) < clientStaleDuration;
  }

  void _applyCors(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, HEAD, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Range, Client-Id, X-Client-Id',
    );
    response.headers.set(
      'Access-Control-Expose-Headers',
      'Content-Length, Content-Range, Accept-Ranges',
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    _applyCors(response);

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    final path = request.uri.path;
    try {
      if (path == '/proxy') {
        await _handleProxy(request);
      } else if (path == '/m3u8') {
        await _handleM3u8(request);
      } else if (path == '/subtitle') {
        await _handleSubtitle(request);
      } else if (path == '/web-receiver/discover.gif') {
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType('image', 'gif');
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        response.headers.contentLength = _transparentGif.length;
        response.add(_transparentGif);
        await response.close();
      } else if (path == '/' ||
          path == '/web-receiver' ||
          path == '/web-receiver/' ||
          path == '/web-receiver/index.html') {
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.html;
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        response.write(_webReceiverHtml);
        await response.close();
      } else if (path == '/web-receiver-io/longPoll') {
        await _handleLongPoll(request);
      } else if (path.startsWith('/web-receiver-io/')) {
        await _handleTelemetry(request, path);
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write('Not Found');
        await response.close();
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
      } catch (_) {}
    }
  }

  /// Opens an upstream request with custom headers, optional Range header,
  /// and manual redirect following up to [maxRedirects] so headers survive
  /// cross-host redirects.
  Future<({HttpClientResponse response, Uri finalUri})> _openUpstream(
    String url, {
    required Map<String, String> headers,
    String method = 'GET',
    String? rangeHeader,
  }) async {
    var currentUri = Uri.parse(url);

    for (var redirectCount = 0;
        redirectCount <= maxRedirects;
        redirectCount++) {
      final upstreamReq = await _httpClient.openUrl(method, currentUri);
      upstreamReq.followRedirects = false;

      headers.forEach((key, value) {
        upstreamReq.headers.set(key, value);
      });
      if (rangeHeader != null && rangeHeader.isNotEmpty) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }

      final upstreamResp = await upstreamReq.close();
      final status = upstreamResp.statusCode;

      if (status == HttpStatus.movedPermanently ||
          status == HttpStatus.found ||
          status == HttpStatus.seeOther ||
          status == HttpStatus.temporaryRedirect ||
          status == HttpStatus.permanentRedirect) {
        final location = upstreamResp.headers.value(HttpHeaders.locationHeader);
        await upstreamResp.drain<void>();
        if (location == null || location.isEmpty) {
          throw HttpException('Redirect without Location header', uri: currentUri);
        }
        currentUri = currentUri.resolve(location);
        if (redirectCount == maxRedirects) {
          throw HttpException('Too many redirects', uri: currentUri);
        }
        continue;
      }

      return (response: upstreamResp, finalUri: currentUri);
    }

    throw HttpException('Too many redirects', uri: currentUri);
  }

  Future<void> _handleProxy(HttpRequest request) async {
    final token = request.uri.queryParameters['id'];
    final entry = token != null ? _tokens[token] : null;
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Unknown proxy token');
      await request.response.close();
      return;
    }

    final range = request.headers.value(HttpHeaders.rangeHeader);
    final method = request.method == 'HEAD' ? 'HEAD' : 'GET';
    final result = await _openUpstream(
      entry.url,
      headers: entry.headers,
      method: method,
      rangeHeader: range,
    );
    final upstream = result.response;
    final res = request.response;

    res.statusCode = upstream.statusCode;

    final contentType = upstream.headers.value(HttpHeaders.contentTypeHeader);
    if (contentType != null) {
      res.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    final contentLength = upstream.headers.value(HttpHeaders.contentLengthHeader);
    if (contentLength != null) {
      res.headers.set(HttpHeaders.contentLengthHeader, contentLength);
    }
    final contentRange = upstream.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      res.headers.set(HttpHeaders.contentRangeHeader, contentRange);
    }
    final acceptRanges = upstream.headers.value(HttpHeaders.acceptRangesHeader);
    res.headers.set(HttpHeaders.acceptRangesHeader, acceptRanges ?? 'bytes');

    if (method == 'HEAD') {
      await upstream.drain<void>();
      await res.close();
      return;
    }

    try {
      await upstream.pipe(res);
    } catch (_) {
      // Downstream client disconnected mid-stream.
    }
  }

  Future<void> _handleM3u8(HttpRequest request) async {
    final token = request.uri.queryParameters['id'];
    final entry = token != null ? _tokens[token] : null;
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Unknown m3u8 token');
      await request.response.close();
      return;
    }

    final result = await _openUpstream(entry.url, headers: entry.headers);
    final upstream = result.response;
    final body = await utf8.decoder.bind(upstream).join();

    if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
      request.response.statusCode = upstream.statusCode;
      request.response.write(body);
      await request.response.close();
      return;
    }

    final rewritten = rewriteM3U8(
      body,
      result.finalUri,
      proxyUrlBuilder: (u) => buildProxyUrl(u, headers: entry.headers),
      m3u8UrlBuilder: (u) => buildM3u8Url(u, headers: entry.headers),
    );

    final res = request.response;
    res.statusCode = HttpStatus.ok;
    res.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/vnd.apple.mpegurl; charset=utf-8',
    );
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    res.write(rewritten);
    await res.close();
  }

  Future<void> _handleSubtitle(HttpRequest request) async {
    final token = request.uri.queryParameters['id'];
    final entry = token != null ? _tokens[token] : null;
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Unknown subtitle token');
      await request.response.close();
      return;
    }

    final result = await _openUpstream(entry.url, headers: entry.headers);
    final upstream = result.response;
    final bytes = await upstream.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );

    if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
      request.response.statusCode = upstream.statusCode;
      await request.response.close();
      return;
    }

    String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException {
      raw = latin1.decode(bytes);
    }

    final vtt = srtToVtt(raw);
    final res = request.response;
    res.statusCode = HttpStatus.ok;
    res.headers.set(HttpHeaders.contentTypeHeader, 'text/vtt; charset=utf-8');
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    res.write(vtt);
    await res.close();
  }

  Future<void> _handleLongPoll(HttpRequest request) async {
    final clientId = request.headers.value('client-id') ??
        request.headers.value('x-client-id') ??
        request.uri.queryParameters['clientId'];

    final res = request.response;
    res.headers.contentType = ContentType.json;
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    if (clientId == null || clientId.trim().isEmpty) {
      res.statusCode = HttpStatus.badRequest;
      res.write(jsonEncode({'error': 'missing Client-Id'}));
      await res.close();
      return;
    }

    if (_activeClientId != null &&
        _activeClientId != clientId &&
        _isActiveClientAlive()) {
      res.statusCode = HttpStatus.conflict;
      res.write(jsonEncode({'error': 'busy'}));
      await res.close();
      return;
    }

    final isNewConnection = _activeClientId != clientId;
    _activeClientId = clientId;
    _lastClientActivity = DateTime.now();

    if (isNewConnection) {
      onReceiverConnectionChanged?.call(true, clientId);
    }

    if (_commandQueue.isNotEmpty) {
      final batch = List<Map<String, dynamic>>.from(_commandQueue);
      _commandQueue.clear();
      res.statusCode = HttpStatus.ok;
      res.write(jsonEncode({'commands': batch}));
      await res.close();
      return;
    }

    // Cancel any stale poll from the same client before attaching a new one.
    if (_pendingPoll != null && !_pendingPoll!.isCompleted) {
      _pendingPoll!.complete(const []);
    }
    _heartbeatTimer?.cancel();

    final completer = Completer<List<Map<String, dynamic>>>();
    _pendingPoll = completer;

    _heartbeatTimer = Timer(heartbeatDuration, () {
      if (!completer.isCompleted) {
        if (identical(_pendingPoll, completer)) {
          _pendingPoll = null;
        }
        completer.complete(const []);
      }
    });

    final commands = await completer.future;
    _lastClientActivity = DateTime.now();

    try {
      res.statusCode = HttpStatus.ok;
      if (commands.isEmpty) {
        res.write('{}');
      } else {
        res.write(jsonEncode({'commands': commands}));
      }
      await res.close();
    } catch (_) {
      // Client closed connection while waiting.
    }
  }

  Future<void> _handleTelemetry(HttpRequest request, String path) async {
    final clientId = request.headers.value('client-id') ??
        request.headers.value('x-client-id');
    final body = await utf8.decoder.bind(request).join();
    Map<String, dynamic> data = const {};
    if (body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}
    }

    if (clientId != null && clientId == _activeClientId) {
      _lastClientActivity = DateTime.now();
    }

    switch (path) {
      case '/web-receiver-io/state':
        final state = data['state']?.toString();
        if (state != null) onStateTelemetry?.call(state);
      case '/web-receiver-io/position':
        final posSec = (data['position'] as num?)?.toDouble() ?? 0.0;
        final durSec = (data['duration'] as num?)?.toDouble() ?? 0.0;
        onPositionTelemetry?.call(
          Duration(milliseconds: (posSec * 1000).round()),
          Duration(milliseconds: (durSec * 1000).round()),
        );
      case '/web-receiver-io/volume':
        final vol = (data['volume'] as num?)?.toDouble() ?? 1.0;
        final muted = data['muted'] == true;
        onVolumeTelemetry?.call(vol.clamp(0.0, 1.0), muted);
      case '/web-receiver-io/error':
        final msg = data['message']?.toString() ?? 'Receiver playback error';
        onErrorTelemetry?.call(msg);
      case '/web-receiver-io/disconnect':
        if (clientId == null || clientId == _activeClientId) {
          clearActiveReceiver();
        }
        onDisconnectTelemetry?.call();
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"ok":true}');
    await request.response.close();
  }

  static const String _webReceiverHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OnlyStream Web Receiver</title>
<script src="https://cdn.jsdelivr.net/npm/hls.js@1/dist/hls.min.js"></script>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body {
    width: 100%; height: 100%;
    background: #0B0B0D; color: #FFFFFF;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    overflow: hidden;
  }
  #stage {
    position: relative; width: 100vw; height: 100vh;
    display: flex; align-items: center; justify-content: center;
    background: #0B0B0D;
  }
  video {
    width: 100%; height: 100%;
    object-fit: contain;
    background: #000000;
    display: none;
  }
  video.active { display: block; }
  #overlay {
    position: absolute; inset: 0;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 14px; padding: 24px; text-align: center;
    background: #0B0B0D;
  }
  #overlay.hidden { display: none; }
  .badge {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 6px 14px; border-radius: 999px;
    background: #141417; border: 1px solid #26262C;
    font-size: 13px; color: #A1A1AA;
  }
  .dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: #34C759;
  }
  .dot.busy { background: #E50914; }
  h1 { font-size: 26px; font-weight: 600; letter-spacing: -0.4px; }
  p { font-size: 15px; color: #A1A1AA; max-width: 420px; }
  #titleBar {
    position: absolute; top: 20px; left: 24px; right: 24px;
    font-size: 18px; font-weight: 600;
    text-shadow: 0 2px 10px rgba(0,0,0,0.8);
    opacity: 0; transition: opacity 0.3s ease;
    pointer-events: none;
  }
  #titleBar.visible { opacity: 1; }
  button {
    margin-top: 8px; padding: 10px 20px;
    background: #FFFFFF; color: #0B0B0D;
    border: none; border-radius: 10px;
    font-size: 14px; font-weight: 600; cursor: pointer;
    display: none;
  }
  button.visible { display: inline-block; }
</style>
</head>
<body>
<div id="stage">
  <video id="video" playsinline controls></video>
  <div id="titleBar"></div>
  <div id="overlay">
    <div class="badge"><span id="dot" class="dot"></span><span id="statusText">Connected — Ready to Cast</span></div>
    <h1>OnlyStream Receiver</h1>
    <p id="subText">Select a video on your phone to start playback on this screen.</p>
    <button id="retryBtn">Retry Connection</button>
  </div>
</div>
<script>
(function() {
  const video = document.getElementById('video');
  const overlay = document.getElementById('overlay');
  const dot = document.getElementById('dot');
  const statusText = document.getElementById('statusText');
  const subText = document.getElementById('subText');
  const titleBar = document.getElementById('titleBar');
  const retryBtn = document.getElementById('retryBtn');

  const clientId = (window.crypto && crypto.randomUUID)
    ? crypto.randomUUID()
    : ('os-' + Math.random().toString(36).slice(2) + Date.now().toString(36));

  let hls = null;
  let running = true;
  let titleTimer = null;

  function showTitle(text) {
    if (!text) return;
    titleBar.textContent = text;
    titleBar.classList.add('visible');
    clearTimeout(titleTimer);
    titleTimer = setTimeout(() => titleBar.classList.remove('visible'), 4000);
  }

  function postTelemetry(endpoint, payload) {
    fetch('/web-receiver-io/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Client-Id': clientId },
      body: JSON.stringify(payload || {})
    }).catch(() => {});
  }

  function clearSubtitles() {
    Array.from(video.querySelectorAll('track')).forEach(t => t.remove());
  }

  function setSubtitles(url, label) {
    clearSubtitles();
    if (!url) return;
    const track = document.createElement('track');
    track.kind = 'subtitles';
    track.label = label || 'Subtitles';
    track.src = url;
    track.default = true;
    video.appendChild(track);
    if (video.textTracks && video.textTracks[0]) {
      video.textTracks[0].mode = 'showing';
    }
  }

  function loadMedia(cmd) {
    if (hls) { hls.destroy(); hls = null; }
    clearSubtitles();
    overlay.classList.add('hidden');
    video.classList.add('active');
    showTitle(cmd.title || '');

    const startPos = Number(cmd.position || 0);
    const applyStart = () => {
      if (startPos > 0 && isFinite(video.duration || Infinity)) {
        try { video.currentTime = startPos; } catch (_) {}
      }
      video.play().catch(() => {});
    };

    if (cmd.posterUrl) video.poster = cmd.posterUrl;
    if (cmd.subtitleUrl) setSubtitles(cmd.subtitleUrl, cmd.subtitleLabel);

    if (cmd.isHls && window.Hls && Hls.isSupported()) {
      hls = new Hls({ enableWorker: true });
      hls.loadSource(cmd.url);
      hls.attachMedia(video);
      hls.on(Hls.Events.MANIFEST_PARSED, applyStart);
      hls.on(Hls.Events.ERROR, (_, data) => {
        if (data && data.fatal) {
          postTelemetry('error', { message: 'HLS error: ' + (data.details || 'fatal') });
        }
      });
    } else {
      video.src = cmd.url;
      video.addEventListener('loadedmetadata', applyStart, { once: true });
      video.load();
    }
  }

  function handleCommand(cmd) {
    if (!cmd || !cmd.type) return;
    switch (cmd.type) {
      case 'loadMedia': loadMedia(cmd); break;
      case 'play': video.play().catch(() => {}); break;
      case 'pause': video.pause(); break;
      case 'stop':
        if (hls) { hls.destroy(); hls = null; }
        video.pause();
        video.removeAttribute('src');
        video.load();
        video.classList.remove('active');
        overlay.classList.remove('hidden');
        postTelemetry('state', { state: 'idle' });
        break;
      case 'setPosition':
        if (typeof cmd.position === 'number') {
          video.currentTime = Math.max(0, cmd.position);
          postTelemetry('position', { position: video.currentTime, duration: video.duration || 0 });
        }
        break;
      case 'setVolume':
        if (typeof cmd.volume === 'number') {
          video.volume = Math.max(0, Math.min(1, cmd.volume));
          video.muted = video.volume === 0;
          postTelemetry('volume', { volume: video.volume, muted: video.muted });
        }
        break;
      case 'setSpeed':
        if (typeof cmd.speed === 'number' && cmd.speed > 0) {
          video.playbackRate = cmd.speed;
        }
        break;
      case 'setSubtitles':
        setSubtitles(cmd.url, cmd.label);
        break;
      case 'stopSubtitles':
        clearSubtitles();
        break;
      case 'zoom':
        video.style.objectFit = cmd.mode === 'cover' ? 'cover' : 'contain';
        break;
      case 'disconnect':
        if (hls) { hls.destroy(); hls = null; }
        video.pause();
        video.removeAttribute('src');
        video.classList.remove('active');
        overlay.classList.remove('hidden');
        statusText.textContent = 'Disconnected';
        subText.textContent = 'Cast session ended.';
        postTelemetry('state', { state: 'idle' });
        break;
    }
  }

  video.addEventListener('playing', () => postTelemetry('state', { state: 'playing' }));
  video.addEventListener('pause', () => {
    postTelemetry('state', { state: 'paused' });
    postTelemetry('position', { position: video.currentTime || 0, duration: video.duration || 0 });
  });
  video.addEventListener('waiting', () => postTelemetry('state', { state: 'buffering' }));
  video.addEventListener('ended', () => postTelemetry('state', { state: 'ended' }));
  video.addEventListener('volumechange', () => postTelemetry('volume', { volume: video.volume, muted: video.muted }));
  video.addEventListener('error', () => postTelemetry('error', { message: 'HTML5 video playback error' }));

  setInterval(() => {
    if (!video.paused && !video.ended && video.readyState >= 2) {
      postTelemetry('position', { position: video.currentTime || 0, duration: video.duration || 0 });
    }
  }, 1000);

  window.addEventListener('beforeunload', () => {
    running = false;
    if (navigator.sendBeacon) {
      navigator.sendBeacon('/web-receiver-io/disconnect', JSON.stringify({ clientId }));
    }
  });

  async function pollLoop() {
    while (running) {
      try {
        const res = await fetch('/web-receiver-io/longPoll', {
          method: 'GET',
          headers: { 'Client-Id': clientId },
          cache: 'no-store'
        });
        if (res.status === 409) {
          dot.classList.add('busy');
          statusText.textContent = 'Receiver Busy';
          subText.textContent = 'Another browser tab or TV is already connected to this OnlyStream session.';
          retryBtn.classList.add('visible');
          overlay.classList.remove('hidden');
          return;
        }
        if (res.ok) {
          dot.classList.remove('busy');
          retryBtn.classList.remove('visible');
          if (!video.classList.contains('active')) {
            statusText.textContent = 'Connected — Ready to Cast';
          }
          const data = await res.json();
          if (Array.isArray(data.commands)) {
            for (const cmd of data.commands) handleCommand(cmd);
          }
        }
      } catch (_) {
        await new Promise(r => setTimeout(r, 1500));
      }
    }
  }

  retryBtn.addEventListener('click', () => {
    retryBtn.classList.remove('visible');
    dot.classList.remove('busy');
    statusText.textContent = 'Reconnecting...';
    pollLoop();
  });

  pollLoop();
})();
</script>
</body>
</html>
''';
}
