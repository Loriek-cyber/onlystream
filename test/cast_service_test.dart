import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onlystream/services/cast/cast_controller.dart';
import 'package:onlystream/services/cast/cast_server.dart';
import 'package:onlystream/services/cast/code_util.dart';
import 'package:onlystream/services/cast/dlna_service.dart';

void main() {
  group('CodeUtil', () {
    test('encodes and decodes RFC1918 private IPv4 ranges via Base36', () {
      const testIps = [
        '192.168.0.1',
        '192.168.1.50',
        '192.168.255.255',
        '10.0.0.12',
        '10.42.100.7',
        '172.16.0.5',
        '172.31.255.254',
      ];

      for (final ip in testIps) {
        final code = CodeUtil.ipToCode(ip);
        expect(code, isNotNull, reason: 'Expected code for $ip');
        final candidates = CodeUtil.codeToCandidateUrls(code!);
        expect(
          candidates,
          contains('http://$ip:${CodeUtil.defaultPort}'),
          reason: 'Expected $ip in candidates for code $code: $candidates',
        );
      }
    });

    test('supports custom Base36 portCode and case-insensitive input', () {
      final ipCode = CodeUtil.ipToCode('192.168.1.50')!;
      final portCode = CodeUtil.portToCode(8080);

      final candidates = CodeUtil.codeToCandidateUrls(
        ' ${ipCode.toLowerCase()} ',
        portCode: portCode.toLowerCase(),
      );
      expect(candidates, contains('http://192.168.1.50:8080'));
    });

    test('rejects non-private and malformed IPv4 addresses', () {
      expect(CodeUtil.ipToCode('8.8.8.8'), isNull);
      expect(CodeUtil.ipToCode('127.0.0.1'), isNull);
      expect(CodeUtil.ipToCode('172.15.0.1'), isNull);
      expect(CodeUtil.ipToCode('172.32.0.1'), isNull);
      expect(CodeUtil.ipToCode('999.168.1.1'), isNull);
      expect(CodeUtil.ipToCode('not-an-ip'), isNull);
      expect(CodeUtil.codeToCandidateUrls(''), isEmpty);
      expect(CodeUtil.codeToCandidateUrls('!!!'), isEmpty);
    });
  });

  group('rewriteM3U8', () {
    test('rewrites master sub-playlists, segments, and URI attributes', () {
      const manifest = '''#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Italian",URI="audio/it.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2500000,AUDIO="aud"
720p/index.m3u8
#EXT-X-KEY:METHOD=AES-128,URI="/keys/enc.key"
#EXT-X-MAP:URI="init.mp4"
#EXTINF:6.0,
seg001.ts
#EXTINF:6.0,
https://cdn.example.com/live/seg002.m4s
''';

      final baseUri = Uri.parse('https://stream.example.com/hls/master.m3u8');
      final rewritten = rewriteM3U8(
        manifest,
        baseUri,
        proxyUrlBuilder: (u) => 'http://192.168.1.50:30001/proxy?u=$u',
        m3u8UrlBuilder: (u) => 'http://192.168.1.50:30001/m3u8?u=$u',
      );

      expect(
        rewritten,
        contains(
          'URI="http://192.168.1.50:30001/m3u8?u=https://stream.example.com/hls/audio/it.m3u8"',
        ),
      );
      expect(
        rewritten,
        contains(
          'http://192.168.1.50:30001/m3u8?u=https://stream.example.com/hls/720p/index.m3u8',
        ),
      );
      expect(
        rewritten,
        contains(
          'URI="http://192.168.1.50:30001/proxy?u=https://stream.example.com/keys/enc.key"',
        ),
      );
      expect(
        rewritten,
        contains(
          'URI="http://192.168.1.50:30001/proxy?u=https://stream.example.com/hls/init.mp4"',
        ),
      );
      expect(
        rewritten,
        contains(
          'http://192.168.1.50:30001/proxy?u=https://stream.example.com/hls/seg001.ts',
        ),
      );
      expect(
        rewritten,
        contains(
          'http://192.168.1.50:30001/proxy?u=https://cdn.example.com/live/seg002.m4s',
        ),
      );
    });
  });

  group('srtToVtt', () {
    test('converts SRT with BOM and CRLF to valid WebVTT', () {
      const srt = '\uFEFF1\r\n'
          '00:00:01,250 --> 00:00:04,500\r\n'
          'Ciao mondo!\r\n\r\n'
          '2\r\n'
          '00:01:05,000 --> 00:01:08,999\r\n'
          'Seconda riga\r\n';

      final vtt = srtToVtt(srt);
      expect(vtt.startsWith('WEBVTT\n\n'), isTrue);
      expect(vtt, contains('00:00:01.250 --> 00:00:04.500'));
      expect(vtt, contains('00:01:05.000 --> 00:01:08.999'));
      expect(vtt, isNot(contains('\r')));
      expect(vtt, isNot(contains('\uFEFF')));
    });

    test('preserves existing WebVTT content', () {
      const existing = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello\n';
      expect(srtToVtt(existing), equals(existing));
    });
  });

  group('CastServer HTTP endpoints', () {
    late HttpServer upstream;
    late CastServer castServer;
    late HttpClient client;
    String? lastUpstreamReferer;
    String? lastUpstreamCookie;

    setUp(() async {
      lastUpstreamReferer = null;
      lastUpstreamCookie = null;

      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((req) async {
        lastUpstreamReferer = req.headers.value('referer');
        lastUpstreamCookie = req.headers.value('cookie');

        if (req.uri.path == '/redirect') {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set(HttpHeaders.locationHeader, '/video.mp4');
          await req.response.close();
          return;
        }

        if (req.uri.path == '/video.mp4') {
          final data = utf8.encode('0123456789ABCDEF');
          final range = req.headers.value(HttpHeaders.rangeHeader);
          if (range == 'bytes=4-7') {
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
            req.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes 4-7/${data.length}',
            );
            req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            req.response.headers.contentLength = 4;
            req.response.add(data.sublist(4, 8));
            await req.response.close();
            return;
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
          req.response.headers.contentLength = data.length;
          req.response.add(data);
          await req.response.close();
          return;
        }

        if (req.uri.path == '/playlist.m3u8') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/vnd.apple.mpegurl',
          );
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
            '#EXTINF:4.0,\n'
            'chunk1.ts\n',
          );
          await req.response.close();
          return;
        }

        if (req.uri.path == '/sub.srt') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            '1\n00:00:02,100 --> 00:00:05,200\nBuongiorno\n',
          );
          await req.response.close();
          return;
        }

        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      });

      castServer = CastServer(
        preferredPort: 0,
        heartbeatDuration: const Duration(milliseconds: 250),
      );
      await castServer.start(advertiseHost: '127.0.0.1');
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await castServer.dispose();
      await upstream.close(force: true);
    });

    test('/proxy forwards custom headers, Range 206, redirects, and CORS',
        () async {
      final proxyUrl = castServer.buildProxyUrl(
        'http://127.0.0.1:${upstream.port}/redirect',
        headers: const {
          'Referer': 'https://example.org/watch',
          'Cookie': 'sid=abc123',
        },
      );

      final req = await client.getUrl(Uri.parse(proxyUrl));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=4-7');
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();

      expect(resp.statusCode, equals(HttpStatus.partialContent));
      expect(body, equals('4567'));
      expect(lastUpstreamReferer, equals('https://example.org/watch'));
      expect(lastUpstreamCookie, equals('sid=abc123'));
      expect(
        resp.headers.value('access-control-allow-origin'),
        equals('*'),
      );
      expect(
        resp.headers.value('access-control-expose-headers'),
        contains('Content-Range'),
      );
      expect(
        resp.headers.value(HttpHeaders.contentRangeHeader),
        equals('bytes 4-7/16'),
      );
    });

    test('/m3u8 fetches with custom headers and rewrites manifest URLs',
        () async {
      final m3u8Url = castServer.buildM3u8Url(
        'http://127.0.0.1:${upstream.port}/playlist.m3u8',
        headers: const {'Referer': 'https://ref.test/'},
      );

      final req = await client.getUrl(Uri.parse(m3u8Url));
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();

      expect(resp.statusCode, equals(HttpStatus.ok));
      expect(lastUpstreamReferer, equals('https://ref.test/'));
      expect(body, contains('${castServer.baseUrl}/proxy?id='));
      expect(body, isNot(contains('chunk1.ts')));
      expect(body, isNot(contains('key.bin')));
    });

    test('/subtitle converts SRT to WebVTT with text/vtt and CORS', () async {
      final subUrl = castServer.buildSubtitleUrl(
        'http://127.0.0.1:${upstream.port}/sub.srt',
      );

      final req = await client.getUrl(Uri.parse(subUrl));
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();

      expect(resp.statusCode, equals(HttpStatus.ok));
      expect(
        resp.headers.value(HttpHeaders.contentTypeHeader),
        contains('text/vtt'),
      );
      expect(resp.headers.value('access-control-allow-origin'), equals('*'));
      expect(body, startsWith('WEBVTT\n\n'));
      expect(body, contains('00:00:02.100 --> 00:00:05.200'));
    });

    test('/web-receiver/discover.gif and /web-receiver/ serve expected assets',
        () async {
      final gifReq = await client.getUrl(
        Uri.parse('${castServer.baseUrl}/web-receiver/discover.gif'),
      );
      final gifResp = await gifReq.close();
      final gifBytes = await gifResp.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      expect(gifResp.statusCode, equals(HttpStatus.ok));
      expect(gifResp.headers.contentType?.mimeType, equals('image/gif'));
      expect(gifBytes.take(6).toList(), equals(utf8.encode('GIF89a')));

      final htmlReq = await client.getUrl(Uri.parse(castServer.webReceiverUrl));
      final htmlResp = await htmlReq.close();
      final html = await utf8.decoder.bind(htmlResp).join();
      expect(htmlResp.statusCode, equals(HttpStatus.ok));
      expect(html, contains('hls.min.js'));
      expect(html, contains('/web-receiver-io/longPoll'));
    });

    test('/web-receiver-io/longPoll delivers commands (200) and returns 409 Busy',
        () async {
      // Start Client A long-poll
      final pollAReq = await client.getUrl(
        Uri.parse('${castServer.baseUrl}/web-receiver-io/longPoll'),
      );
      pollAReq.headers.set('Client-Id', 'client-a');
      final pollAFuture = pollAReq.close();

      // Give server a moment to register Client A's pending poll
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Client B attempts to long-poll -> must receive 409 Conflict
      final pollBReq = await client.getUrl(
        Uri.parse('${castServer.baseUrl}/web-receiver-io/longPoll'),
      );
      pollBReq.headers.set('Client-Id', 'client-b');
      final pollBResp = await pollBReq.close();
      final pollBBody = await utf8.decoder.bind(pollBResp).join();

      expect(pollBResp.statusCode, equals(HttpStatus.conflict));
      expect(pollBBody, contains('busy'));

      // Enqueue command for Client A -> resolves immediately with 200
      castServer.enqueueCommand({
        'type': 'loadMedia',
        'url': 'http://127.0.0.1/test.mp4',
        'title': 'Test Movie',
      });

      final pollAResp = await pollAFuture;
      final pollABody = await utf8.decoder.bind(pollAResp).join();
      expect(pollAResp.statusCode, equals(HttpStatus.ok));
      final decoded = jsonDecode(pollABody) as Map<String, dynamic>;
      expect(decoded['commands'], isA<List<dynamic>>());
      expect(
        (decoded['commands'] as List<dynamic>).first['type'],
        equals('loadMedia'),
      );

      // Heartbeat returns {} when no commands arrive within heartbeatDuration
      final hbReq = await client.getUrl(
        Uri.parse('${castServer.baseUrl}/web-receiver-io/longPoll'),
      );
      hbReq.headers.set('Client-Id', 'client-a');
      final hbResp = await hbReq.close();
      final hbBody = await utf8.decoder.bind(hbResp).join();
      expect(hbResp.statusCode, equals(HttpStatus.ok));
      expect(hbBody, equals('{}'));
    });

    test('CastController emits telemetry position updates from Web Receiver',
        () async {
      final controller = CastController(server: castServer);
      await controller.startServer(advertiseHost: '127.0.0.1');

      final updates = <CastPositionUpdate>[];
      final sub = controller.positionStream.listen(updates.add);

      final posReq = await client.postUrl(
        Uri.parse('${castServer.baseUrl}/web-receiver-io/position'),
      );
      posReq.headers.contentType = ContentType.json;
      posReq.write(jsonEncode({'position': 125.5, 'duration': 3600.0}));
      final posResp = await posReq.close();
      await posResp.drain<void>();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(updates, isNotEmpty);
      expect(updates.last.position, equals(const Duration(milliseconds: 125500)));
      expect(updates.last.duration, equals(const Duration(seconds: 3600)));

      await sub.cancel();
    });
  });

  group('DlnaService XML / DIDL-Lite / SOAP parsing', () {
    test('parseDeviceDescription extracts friendlyName and service controlURLs',
        () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>Living Room LG OLED &amp; TV</friendlyName>
    <manufacturer>LG Electronics</manufacturer>
    <modelName>OLED55C3</modelName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/upnp/control/AVTransport1</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>upnp/control/RenderingControl1</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';

      final device = DlnaService.parseDeviceDescription(
        xml,
        Uri.parse('http://192.168.1.88:1400/device/desc.xml'),
        usn: 'uuid:lg-oled-1',
      );

      expect(device, isNotNull);
      expect(device!.friendlyName, equals('Living Room LG OLED & TV'));
      expect(device.manufacturer, equals('LG Electronics'));
      expect(device.modelName, equals('OLED55C3'));
      expect(
        device.avTransportControlUrl,
        equals('http://192.168.1.88:1400/upnp/control/AVTransport1'),
      );
      expect(
        device.renderingControlUrl,
        equals('http://192.168.1.88:1400/device/upnp/control/RenderingControl1'),
      );
    });

    test('buildDidlLite escapes XML entities and includes subtitles', () {
      final didl = DlnaService.buildDidlLite(
        url: 'http://192.168.1.50:30001/proxy?id=abc&x=1',
        title: 'Tom & Jerry <S01E01>',
        mimeType: 'video/mp4',
        subtitleUrl: 'http://192.168.1.50:30001/subtitle?id=sub1',
      );

      expect(didl, contains('<dc:title>Tom &amp; Jerry &lt;S01E01&gt;</dc:title>'));
      expect(didl, contains('<upnp:class>object.item.videoItem</upnp:class>'));
      expect(
        didl,
        contains(
          '<res protocolInfo="http-get:*:video/mp4:*">http://192.168.1.50:30001/proxy?id=abc&amp;x=1</res>',
        ),
      );
      expect(didl, contains('http://192.168.1.50:30001/subtitle?id=sub1'));
    });

    test('buildSoapEnvelope generates valid SOAP 1.1 action XML', () {
      final soap = DlnaService.buildSoapEnvelope(
        serviceType: DlnaService.avTransportServiceType,
        action: 'Seek',
        args: const {
          'InstanceID': '0',
          'Unit': 'REL_TIME',
          'Target': '00:15:30',
        },
      );

      expect(soap, contains('xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"'));
      expect(soap, contains('<u:Seek '));
      expect(soap, contains('<Unit>REL_TIME</Unit>'));
      expect(soap, contains('<Target>00:15:30</Target>'));
    });

    test('parsePositionInfo parses RelTime and TrackDuration', () {
      const soapResp = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <Track>1</Track>
      <TrackDuration>01:42:15</TrackDuration>
      <TrackURI>http://192.168.1.50:30001/proxy?id=123</TrackURI>
      <RelTime>00:12:34.500</RelTime>
    </u:GetPositionInfoResponse>
  </s:Body>
</s:Envelope>''';

      final info = DlnaService.parsePositionInfo(soapResp);
      expect(
        info.position,
        equals(const Duration(minutes: 12, seconds: 34, milliseconds: 500)),
      );
      expect(
        info.duration,
        equals(const Duration(hours: 1, minutes: 42, seconds: 15)),
      );
      expect(info.trackUri, equals('http://192.168.1.50:30001/proxy?id=123'));

      expect(DlnaService.parseUpnpDuration('NOT_IMPLEMENTED'), Duration.zero);
      expect(
        DlnaService.formatUpnpDuration(const Duration(hours: 1, minutes: 5, seconds: 9)),
        equals('01:05:09'),
      );
    });
  });
}
