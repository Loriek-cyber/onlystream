import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onlystream/models/library.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/torrent_session_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigService and CompanionServerBridge', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('onlystream_cfg_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists server mode, URL, presets, and playback preferences', () async {
      final mockHttp = MockClient(
        (_) async => http.Response(
          json.encode({'status': 'ok', 'service': 'easystreamapi', 'version': '1.0.0'}),
          200,
        ),
      );

      final config = ConfigService(
        storageDirOverride: tempDir,
        httpClient: mockHttp,
        isAndroidOverride: true,
      );
      await config.init(checkHealthOnInit: false);

      expect(config.serverMode, 'local');
      expect(config.baseUrl, 'http://127.0.0.1:5555');

      await config.setRemoteUrl('192.168.1.77', presetName: 'NAS');
      await config.setPreferences(
        language: 'en',
        quality: '720p',
        source: 'torrent',
      );

      expect(config.serverMode, 'remote');
      expect(config.baseUrl, 'http://192.168.1.77:5555');
      expect(config.presets.any((p) => p.name == 'NAS'), isTrue);

      final reloaded = ConfigService(
        storageDirOverride: tempDir,
        httpClient: mockHttp,
        isAndroidOverride: true,
      );
      await reloaded.init(checkHealthOnInit: false);

      expect(reloaded.serverMode, 'remote');
      expect(reloaded.remoteUrl, 'http://192.168.1.77:5555');
      expect(reloaded.language, 'en');
      expect(reloaded.quality, '720p');
      expect(reloaded.source, 'torrent');
      expect(reloaded.presets.any((p) => p.name == 'NAS'), isTrue);
    });

    test('uses remote mode when API_URL env override is set on Android', () async {
      final config = ConfigService(
        storageDirOverride: tempDir,
        isAndroidOverride: true,
        apiUrlEnvOverride: 'http://10.0.2.2:5555',
      );
      await config.init(checkHealthOnInit: false);

      expect(config.serverMode, 'remote');
      expect(config.baseUrl, 'http://10.0.2.2:5555');
    });

    test('CompanionServerBridge safely handles non-Android and MissingPluginException', () async {
      final desktopBridge = CompanionServerBridge(isAndroidOverride: false);
      expect(await desktopBridge.isInstalled(), isFalse);
      expect(await desktopBridge.startServer(), isFalse);
      expect(await desktopBridge.stopServer(), isFalse);

      final missingChannelBridge = CompanionServerBridge(
        channel: const MethodChannel('com.loriek.onlystream/missing_test'),
        isAndroidOverride: true,
      );
      expect(await missingChannelBridge.isInstalled(), isFalse);
      expect(await missingChannelBridge.startServer(), isFalse);
      expect(await missingChannelBridge.stopServer(), isFalse);

      const channel = MethodChannel('com.loriek.onlystream/companion_test');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final androidBridge = CompanionServerBridge(
        channel: channel,
        isAndroidOverride: true,
      );
      expect(await androidBridge.isInstalled(), isTrue);
      expect(await androidBridge.startServer(), isTrue);
      expect(await androidBridge.stopServer(), isTrue);
      expect(calls, ['isInstalled', 'startServer', 'stopServer']);
    });
  });

  group('LibraryService persistence and server sync', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('onlystream_lib_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('supports optimistic mutations, offline cache reload, and server sync', () async {
      final serverItems = <String, Map<String, dynamic>>{};
      var serverReachable = true;

      final mockHttp = MockClient((req) async {
        if (!serverReachable) {
          throw const SocketException('Offline');
        }
        if (req.url.path == '/library') {
          final all = serverItems.values.toList();
          return http.Response(
            json.encode({
              'continue_watching':
                  all.where((e) => e['status'] == 'watching').toList(),
              'saved': all.where((e) => e['status'] == 'saved').toList(),
              'completed':
                  all.where((e) => e['status'] == 'completed').toList(),
              'items': all,
            }),
            200,
          );
        }
        if (req.url.path == '/library/tv/1396' && req.method == 'PUT') {
          final body = json.decode(req.body) as Map<String, dynamic>;
          final item = {
            'id': 1396,
            'kind': 'tv',
            'is_anime': body['is_anime'] ?? false,
            'title': body['title'],
            'status': body['status'],
            'position_secs': 0,
            'duration_secs': 0,
            'watched_episodes': <String>[],
            'updated_at': '2026-11-23T12:00:00Z',
            'has_new_episodes': false,
            'new_episodes_count': 0,
          };
          serverItems['tv:1396'] = item;
          return http.Response(json.encode(item), 200);
        }
        if (req.url.path == '/library/tv/1396/progress') {
          final body = json.decode(req.body) as Map<String, dynamic>;
          final item = {
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': body['title'],
            'status': 'watching',
            'current_season': body['season'],
            'current_episode': body['episode'],
            'position_secs': body['position_secs'],
            'duration_secs': body['duration_secs'],
            'watched_episodes':
                serverItems['tv:1396']?['watched_episodes'] ?? <String>[],
            'updated_at': '2026-11-23T12:05:00Z',
            'has_new_episodes': false,
            'new_episodes_count': 0,
          };
          serverItems['tv:1396'] = item;
          return http.Response(json.encode(item), 200);
        }
        if (req.url.path == '/library/tv/1396/watched') {
          final body = json.decode(req.body) as Map<String, dynamic>;
          final watched = body['watched'] == true;
          final eps = watched ? ['S1E1'] : <String>[];
          final item = {
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': body['title'],
            'status': 'watching',
            'current_season': 1,
            'current_episode': 1,
            'position_secs': 150,
            'duration_secs': 2400,
            'watched_episodes': eps,
            'updated_at': '2026-11-23T12:06:00Z',
            'has_new_episodes': false,
            'new_episodes_count': 0,
          };
          serverItems['tv:1396'] = item;
          return http.Response(json.encode(item), 200);
        }
        if (req.url.path == '/library/tv/1396' && req.method == 'DELETE') {
          serverItems.remove('tv:1396');
          return http.Response(json.encode({'deleted': true}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final config = ConfigService(
        storageDirOverride: tempDir,
        httpClient: mockHttp,
        isAndroidOverride: false,
      );
      await config.init(checkHealthOnInit: false);
      final api = ApiClient(config: config, httpClient: mockHttp);

      final library = LibraryService(
        apiClient: api,
        configService: config,
        storageDirOverride: tempDir,
      );
      await library.init(syncOnInit: false);

      await library.toggleSaved(
        kind: MediaKind.tv,
        id: 1396,
        isAnime: false,
        title: 'Breaking Bad',
      );
      expect(library.isTracked(MediaKind.tv, 1396), isTrue);
      expect(library.saved.length, 1);

      await library.reportProgress(
        kind: MediaKind.tv,
        id: 1396,
        isAnime: false,
        title: 'Breaking Bad',
        season: 1,
        episode: 1,
        positionSecs: 150,
        durationSecs: 2400,
      );
      expect(library.continueWatching.single.positionSecs, 150);

      await library.toggleEpisodeWatched(
        kind: MediaKind.tv,
        id: 1396,
        season: 1,
        episode: 1,
        watched: true,
        isAnime: false,
        title: 'Breaking Bad',
      );
      expect(library.isEpisodeWatched(MediaKind.tv, 1396, 1, 1), isTrue);

      // Give background cache write a moment, then verify offline fallback restore.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      serverReachable = false;

      final offlineLibrary = LibraryService(
        apiClient: api,
        configService: config,
        storageDirOverride: tempDir,
      );
      await offlineLibrary.init(syncOnInit: false);
      expect(offlineLibrary.isTracked(MediaKind.tv, 1396), isTrue);
      expect(offlineLibrary.isEpisodeWatched(MediaKind.tv, 1396, 1, 1), isTrue);

      await offlineLibrary.refresh();
      expect(offlineLibrary.isOffline, isTrue);
      expect(offlineLibrary.continueWatching.length, 1);

      serverReachable = true;
      await library.remove(MediaKind.tv, 1396);
      expect(library.isTracked(MediaKind.tv, 1396), isFalse);
    });
  });

  group('TorrentSessionGuard', () {
    test('stops active torrent idempotently and on switches', () async {
      final deletedHashes = <String>[];
      final api = ApiClient(
        baseUrlProvider: () => 'http://localhost:5555',
        httpClient: MockClient((req) async {
          if (req.method == 'DELETE' && req.url.path.startsWith('/torrents/')) {
            deletedHashes.add(req.url.path.replaceFirst('/torrents/', ''));
            return http.Response(json.encode({'status': 'stopped'}), 200);
          }
          return http.Response('Not Found', 404);
        }),
      );

      final guard = TorrentSessionGuard(apiClient: api);

      // Switching torrent A -> torrent B stops A.
      await guard.activateTorrent('HASH_A');
      expect(guard.activeInfoHash, 'hash_a');
      await guard.activateTorrent('HASH_B');
      expect(guard.activeInfoHash, 'hash_b');
      expect(deletedHashes, ['hash_a']);

      // Switching torrent B -> HLS stops B.
      await guard.switchToHls();
      expect(guard.hasActiveTorrent, isFalse);
      expect(deletedHashes, ['hash_a', 'hash_b']);

      // Idempotent stopActive does not issue duplicate DELETE requests.
      await guard.stopActive();
      await guard.stopActive();
      expect(deletedHashes, ['hash_a', 'hash_b']);
    });
  });
}
