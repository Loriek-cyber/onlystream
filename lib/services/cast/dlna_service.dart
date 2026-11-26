import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A discovered UPnP / DLNA MediaRenderer device on the local network.
class DlnaDevice {
  const DlnaDevice({
    required this.usn,
    required this.friendlyName,
    required this.location,
    required this.avTransportControlUrl,
    this.renderingControlUrl,
    this.manufacturer,
    this.modelName,
  });

  final String usn;
  final String friendlyName;
  final String location;
  final String avTransportControlUrl;
  final String? renderingControlUrl;
  final String? manufacturer;
  final String? modelName;

  String get subtitle {
    final parts = <String>[
      if (manufacturer != null && manufacturer!.isNotEmpty) manufacturer!,
      if (modelName != null && modelName!.isNotEmpty) modelName!,
    ];
    return parts.isEmpty ? 'DLNA Media Renderer' : parts.join(' • ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DlnaDevice &&
          avTransportControlUrl == other.avTransportControlUrl;

  @override
  int get hashCode => avTransportControlUrl.hashCode;

  @override
  String toString() =>
      'DlnaDevice(friendlyName: $friendlyName, avTransport: $avTransportControlUrl)';
}

/// Playback position and duration returned by UPnP `GetPositionInfo`.
class DlnaPositionInfo {
  const DlnaPositionInfo({
    required this.position,
    required this.duration,
    this.trackUri,
  });

  final Duration position;
  final Duration duration;
  final String? trackUri;
}

/// Pure-Dart SSDP discovery and UPnP AVTransport / RenderingControl SOAP client.
class DlnaService {
  DlnaService({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 5);
  }

  static const String ssdpAddress = '239.255.255.250';
  static const int ssdpPort = 1900;
  static const String mediaRendererSt =
      'urn:schemas-upnp-org:device:MediaRenderer:1';
  static const String avTransportServiceType =
      'urn:schemas-upnp-org:service:AVTransport:1';
  static const String renderingControlServiceType =
      'urn:schemas-upnp-org:service:RenderingControl:1';

  final HttpClient _httpClient;

  /// Discovers DLNA MediaRenderer devices via UDP multicast SSDP M-SEARCH.
  Future<List<DlnaDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discoveredLocations = <String, String>{}; // location -> usn
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      final payload = utf8.encode(
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $ssdpAddress:$ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: ${timeout.inSeconds.clamp(1, 5)}\r\n'
        'ST: $mediaRendererSt\r\n'
        '\r\n',
      );

      final multicastAddr = InternetAddress(ssdpAddress);
      final completer = Completer<void>();

      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final location = parseSsdpHeader(text, 'LOCATION');
        if (location != null && location.isNotEmpty) {
          final usn = parseSsdpHeader(text, 'USN') ?? location;
          discoveredLocations.putIfAbsent(location, () => usn);
        }
      });

      socket.send(payload, multicastAddr, ssdpPort);
      // Send a second probe after 250ms for UDP reliability on Wi-Fi.
      Timer(const Duration(milliseconds: 250), () {
        try {
          socket?.send(payload, multicastAddr, ssdpPort);
        } catch (_) {}
      });

      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
      await sub.cancel();
    } catch (_) {
      // Network/multicast unavailable (e.g. emulator or sandbox); return empty.
    } finally {
      socket?.close();
    }

    if (discoveredLocations.isEmpty) return const [];

    final devices = <DlnaDevice>[];
    final seenControlUrls = <String>{};

    await Future.wait(
      discoveredLocations.entries.map((entry) async {
        final device = await _fetchDeviceDescription(
          entry.key,
          usn: entry.value,
        );
        if (device != null &&
            seenControlUrls.add(device.avTransportControlUrl)) {
          devices.add(device);
        }
      }),
    );

    devices.sort((a, b) => a.friendlyName.compareTo(b.friendlyName));
    return devices;
  }

  Future<DlnaDevice?> _fetchDeviceDescription(
    String location, {
    required String usn,
  }) async {
    try {
      final uri = Uri.parse(location);
      final req = await _httpClient.getUrl(uri).timeout(
            const Duration(seconds: 4),
          );
      final resp = await req.close().timeout(const Duration(seconds: 4));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        await resp.drain<void>();
        return null;
      }
      final body = await utf8.decoder.bind(resp).join();
      return parseDeviceDescription(body, uri, usn: usn);
    } catch (_) {
      return null;
    }
  }

  /// Loads a media URL onto the DLNA renderer via `SetAVTransportURI`.
  Future<void> setAvTransportUri(
    DlnaDevice device, {
    required String mediaUrl,
    required String title,
    String mimeType = 'video/mp4',
    String? subtitleUrl,
    String? posterUrl,
  }) async {
    final metadata = buildDidlLite(
      url: mediaUrl,
      title: title,
      mimeType: mimeType,
      subtitleUrl: subtitleUrl,
      posterUrl: posterUrl,
    );

    await _sendSoapAction(
      controlUrl: device.avTransportControlUrl,
      serviceType: avTransportServiceType,
      action: 'SetAVTransportURI',
      args: {
        'InstanceID': '0',
        'CurrentURI': mediaUrl,
        'CurrentURIMetaData': metadata,
      },
    );
  }

  /// Sends `Play` (`Speed=1`) to `AVTransport:1`.
  Future<void> play(DlnaDevice device) async {
    await _sendSoapAction(
      controlUrl: device.avTransportControlUrl,
      serviceType: avTransportServiceType,
      action: 'Play',
      args: const {
        'InstanceID': '0',
        'Speed': '1',
      },
    );
  }

  /// Sends `Pause` to `AVTransport:1`.
  Future<void> pause(DlnaDevice device) async {
    await _sendSoapAction(
      controlUrl: device.avTransportControlUrl,
      serviceType: avTransportServiceType,
      action: 'Pause',
      args: const {
        'InstanceID': '0',
      },
    );
  }

  /// Sends `Stop` to `AVTransport:1`.
  Future<void> stop(DlnaDevice device) async {
    await _sendSoapAction(
      controlUrl: device.avTransportControlUrl,
      serviceType: avTransportServiceType,
      action: 'Stop',
      args: const {
        'InstanceID': '0',
      },
    );
  }

  /// Seeks to [position] using `REL_TIME` on `AVTransport:1`.
  Future<void> seek(DlnaDevice device, Duration position) async {
    final safePos = position.isNegative ? Duration.zero : position;
    await _sendSoapAction(
      controlUrl: device.avTransportControlUrl,
      serviceType: avTransportServiceType,
      action: 'Seek',
      args: {
        'InstanceID': '0',
        'Unit': 'REL_TIME',
        'Target': formatUpnpDuration(safePos),
      },
    );
  }

  /// Queries `GetPositionInfo` on `AVTransport:1` and parses `RelTime` &
  /// `TrackDuration`.
  Future<DlnaPositionInfo?> getPositionInfo(DlnaDevice device) async {
    try {
      final responseXml = await _sendSoapAction(
        controlUrl: device.avTransportControlUrl,
        serviceType: avTransportServiceType,
        action: 'GetPositionInfo',
        args: const {
          'InstanceID': '0',
        },
      );
      return parsePositionInfo(responseXml);
    } catch (_) {
      return null;
    }
  }

  /// Sets master volume (`0..100`) on `RenderingControl:1` if supported.
  Future<void> setVolume(DlnaDevice device, int volumePercent) async {
    final controlUrl = device.renderingControlUrl;
    if (controlUrl == null || controlUrl.isEmpty) return;

    final clamped = volumePercent.clamp(0, 100);
    await _sendSoapAction(
      controlUrl: controlUrl,
      serviceType: renderingControlServiceType,
      action: 'SetVolume',
      args: {
        'InstanceID': '0',
        'Channel': 'Master',
        'DesiredVolume': '$clamped',
      },
    );
  }

  Future<String> _sendSoapAction({
    required String controlUrl,
    required String serviceType,
    required String action,
    required Map<String, String> args,
  }) async {
    final envelope = buildSoapEnvelope(
      serviceType: serviceType,
      action: action,
      args: args,
    );
    final uri = Uri.parse(controlUrl);
    final req = await _httpClient.postUrl(uri).timeout(
          const Duration(seconds: 5),
        );
    req.headers.set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"');
    req.headers.set('SOAPACTION', '"$serviceType#$action"');
    final bytes = utf8.encode(envelope);
    req.headers.contentLength = bytes.length;
    req.add(bytes);

    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await utf8.decoder.bind(resp).join();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'DLNA SOAP $action failed (${resp.statusCode}): $body',
        uri: uri,
      );
    }
    return body;
  }

  /// Closes the underlying HTTP client.
  void dispose() {
    _httpClient.close(force: true);
  }

  // ---------------------------------------------------------------------------
  // Pure static XML / SSDP / SOAP helpers (unit-testable)
  // ---------------------------------------------------------------------------

  /// Extracts a case-insensitive header value from an SSDP HTTP response.
  static String? parseSsdpHeader(String response, String headerName) {
    final regex = RegExp(
      '^${RegExp.escape(headerName)}\\s*:\\s*(.+)\$',
      caseSensitive: false,
      multiLine: true,
    );
    final match = regex.firstMatch(response);
    return match?.group(1)?.trim();
  }

  /// Parses a UPnP device description XML document and extracts `friendlyName`,
  /// `AVTransport:1` `controlURL`, and `RenderingControl:1` `controlURL`.
  static DlnaDevice? parseDeviceDescription(
    String xml,
    Uri locationUri, {
    String? usn,
  }) {
    final friendlyName = _extractTagText(xml, 'friendlyName');
    if (friendlyName == null || friendlyName.isEmpty) return null;

    final manufacturer = _extractTagText(xml, 'manufacturer');
    final modelName = _extractTagText(xml, 'modelName');

    final urlBaseText = _extractTagText(xml, 'URLBase');
    final baseUri = (urlBaseText != null && urlBaseText.isNotEmpty)
        ? (Uri.tryParse(urlBaseText) ?? locationUri)
        : locationUri;

    String? avTransportUrl;
    String? renderingControlUrl;

    final serviceRegex = RegExp(
      r'<(?:[a-zA-Z0-9_-]+:)?service\b[^>]*>([\s\S]*?)</(?:[a-zA-Z0-9_-]+:)?service>',
      caseSensitive: false,
    );

    for (final match in serviceRegex.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final serviceType = _extractTagText(block, 'serviceType') ?? '';
      final controlUrl = _extractTagText(block, 'controlURL');
      if (controlUrl == null || controlUrl.isEmpty) continue;

      final resolved = baseUri.resolve(controlUrl.trim()).toString();
      if (serviceType.contains('AVTransport:1')) {
        avTransportUrl ??= resolved;
      } else if (serviceType.contains('RenderingControl:1')) {
        renderingControlUrl ??= resolved;
      }
    }

    if (avTransportUrl == null) return null;

    return DlnaDevice(
      usn: usn ?? locationUri.toString(),
      friendlyName: xmlUnescape(friendlyName),
      location: locationUri.toString(),
      avTransportControlUrl: avTransportUrl,
      renderingControlUrl: renderingControlUrl,
      manufacturer: manufacturer != null ? xmlUnescape(manufacturer) : null,
      modelName: modelName != null ? xmlUnescape(modelName) : null,
    );
  }

  /// Builds a DIDL-Lite XML metadata payload for `SetAVTransportURI`.
  static String buildDidlLite({
    required String url,
    required String title,
    String mimeType = 'video/mp4',
    String? subtitleUrl,
    String? posterUrl,
  }) {
    final escapedUrl = xmlEscape(url);
    final escapedTitle = xmlEscape(title);
    final escapedMime = xmlEscape(mimeType);

    final buffer = StringBuffer()
      ..write(
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
        'xmlns:sec="http://www.sec.co.kr/">',
      )
      ..write('<item id="0" parentID="-1" restricted="1">')
      ..write('<dc:title>$escapedTitle</dc:title>')
      ..write('<upnp:class>object.item.videoItem</upnp:class>')
      ..write(
        '<res protocolInfo="http-get:*:$escapedMime:*">$escapedUrl</res>',
      );

    if (posterUrl != null && posterUrl.isNotEmpty) {
      buffer.write(
        '<upnp:albumArtURI>${xmlEscape(posterUrl)}</upnp:albumArtURI>',
      );
    }

    if (subtitleUrl != null && subtitleUrl.isNotEmpty) {
      final escapedSub = xmlEscape(subtitleUrl);
      buffer
        ..write(
          '<res protocolInfo="http-get:*:text/vtt:*">$escapedSub</res>',
        )
        ..write(
          '<sec:CaptionInfoEx sec:type="vtt">$escapedSub</sec:CaptionInfoEx>',
        );
    }

    buffer.write('</item></DIDL-Lite>');
    return buffer.toString();
  }

  /// Builds a UPnP SOAP 1.1 XML envelope.
  static String buildSoapEnvelope({
    required String serviceType,
    required String action,
    required Map<String, String> args,
  }) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>')
      ..write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
      )
      ..write('<s:Body>')
      ..write('<u:$action xmlns:u="${xmlEscape(serviceType)}">');

    for (final entry in args.entries) {
      buffer.write(
        '<${entry.key}>${xmlEscape(entry.value)}</${entry.key}>',
      );
    }

    buffer
      ..write('</u:$action>')
      ..write('</s:Body>')
      ..write('</s:Envelope>');
    return buffer.toString();
  }

  /// Parses a `GetPositionInfoResponse` SOAP XML body.
  static DlnaPositionInfo parsePositionInfo(String soapXml) {
    final relTime = _extractTagText(soapXml, 'RelTime') ?? '00:00:00';
    final trackDuration =
        _extractTagText(soapXml, 'TrackDuration') ?? '00:00:00';
    final trackUri = _extractTagText(soapXml, 'TrackURI');

    return DlnaPositionInfo(
      position: parseUpnpDuration(relTime),
      duration: parseUpnpDuration(trackDuration),
      trackUri:
          (trackUri != null && trackUri.isNotEmpty) ? xmlUnescape(trackUri) : null,
    );
  }

  /// Parses UPnP duration (`H:MM:SS` or `HH:MM:SS.fff`) into a [Duration].
  static Duration parseUpnpDuration(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty ||
        trimmed.toUpperCase() == 'NOT_IMPLEMENTED' ||
        trimmed.toUpperCase() == 'UNKNOWN') {
      return Duration.zero;
    }

    final parts = trimmed.split(':');
    if (parts.length != 3) return Duration.zero;

    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final secParts = parts[2].split('.');
    final seconds = int.tryParse(secParts[0]) ?? 0;
    var millis = 0;
    if (secParts.length > 1) {
      final frac = secParts[1].padRight(3, '0').substring(0, 3);
      millis = int.tryParse(frac) ?? 0;
    }

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  /// Formats a [Duration] into UPnP `HH:MM:SS`.
  static String formatUpnpDuration(Duration duration) {
    final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static String xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String xmlUnescape(String input) {
    return input
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&gt;', '>')
        .replaceAll('&lt;', '<')
        .replaceAll('&amp;', '&');
  }

  static String? _extractTagText(String xml, String tagName) {
    final regex = RegExp(
      '<(?:[a-zA-Z0-9_-]+:)?${RegExp.escape(tagName)}\\b[^>]*>([\\s\\S]*?)</(?:[a-zA-Z0-9_-]+:)?${RegExp.escape(tagName)}>',
      caseSensitive: false,
    );
    return regex.firstMatch(xml)?.group(1)?.trim();
  }
}
