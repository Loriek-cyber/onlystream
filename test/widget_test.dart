import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onlystream/main.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/screens/app_shell.dart';
import 'package:onlystream/screens/media_detail_screen.dart';
import 'package:onlystream/screens/settings_screen.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';

class FakeOpenCall {
  final String url;
  final Map<String, String>? httpHeaders;
  final Duration start;

  const FakeOpenCall(this.url, this.httpHeaders, this.start);
}

class FakePlayerAdapter implements PlayerAdapter {
  final playingCtrl = StreamController<bool>.broadcast();
  final bufferingCtrl = StreamController<bool>.broadcast();
  final positionCtrl = StreamController<Duration>.broadcast();
  final durationCtrl = StreamController<Duration>.broadcast();
  final completedCtrl = StreamController<bool>.broadcast();
  final audioTracksCtrl = StreamController<List<PlayerTrackItem>>.broadcast();
  final subtitleTracksCtrl =
      StreamController<List<PlayerTrackItem>>.broadcast();
  final activeAudioCtrl = StreamController<String?>.broadcast();
  final activeSubtitleCtrl = StreamController<String?>.broadcast();
  final errorCtrl = StreamController<String>.broadcast();

  final List<FakeOpenCall> openCalls = [];
  final List<PlayerTrackItem> selectedAudioTracks = [];
  final List<PlayerTrackItem?> selectedSubtitleTracks = [];
  bool disposed = false;
  bool paused = false;

  @override
  Stream<bool> get playingStream => playingCtrl.stream;
  @override
  Stream<bool> get bufferingStream => bufferingCtrl.stream;
  @override
  Stream<Duration> get positionStream => positionCtrl.stream;
  @override
  Stream<Duration> get durationStream => durationCtrl.stream;
  @override
  Stream<bool> get completedStream => completedCtrl.stream;
  @override
  Stream<List<PlayerTrackItem>> get audioTracksStream => audioTracksCtrl.stream;
  @override
  Stream<List<PlayerTrackItem>> get subtitleTracksStream =>
      subtitleTracksCtrl.stream;
  @override
  Stream<String?> get activeAudioIdStream => activeAudioCtrl.stream;
  @override
  Stream<String?> get activeSubtitleIdStream => activeSubtitleCtrl.stream;
  @override
  Stream<String> get errorStream => errorCtrl.stream;

  @override
  Future<void> open(
    String url, {
    Map<String, String>? httpHeaders,
    Duration start = Duration.zero,
  }) async {
    openCalls.add(FakeOpenCall(url, httpHeaders, start));
    playingCtrl.add(true);
    durationCtrl.add(const Duration(minutes: 45));
    positionCtrl.add(start);
  }

  @override
  Future<void> playOrPause() async {
    paused = !paused;
    playingCtrl.add(!paused);
  }

  @override
  Future<void> pause() async {
    paused = true;
    playingCtrl.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    positionCtrl.add(position);
  }

  @override
  Future<void> setAudioTrack(PlayerTrackItem track) async {
    selectedAudioTracks.add(track);
    activeAudioCtrl.add(track.id);
  }

  @override
  Future<void> setSubtitleTrack(PlayerTrackItem? track) async {
    selectedSubtitleTracks.add(track);
    activeSubtitleCtrl.add(track?.id ?? 'no');
  }

  @override
  Widget buildVideoView(BuildContext context) {
    return const ColoredBox(
      key: Key('fake_video_surface'),
      color: Colors.black,
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await Future.wait([
      playingCtrl.close(),
      bufferingCtrl.close(),
      positionCtrl.close(),
      durationCtrl.close(),
      completedCtrl.close(),
      audioTracksCtrl.close(),
      subtitleTracksCtrl.close(),
      activeAudioCtrl.close(),
      activeSubtitleCtrl.close(),
      errorCtrl.close(),
    ]);
  }
}

class _TestHarness {
  late ConfigService config;
  late ApiClient api;
  late LibraryService library;
  late TorrentSessionGuard torrentGuard;

  final List<String> deletedTorrentHashes = [];
  final List<String> resolveQueries = [];
  final List<String> searchQueries = [];
  final List<Map<String, dynamic>> watchedPayloads = [];
  bool online = true;

  Future<void> init({bool isAndroid = false}) async {
    final client = MockClient((req) async {
      if (!online && req.url.path != '/health') {
        throw const SocketException('Offline');
      }

      if (req.url.path == '/health') {
        if (!online) {
          throw const SocketException('Offline');
        }
        return http.Response(
          json.encode({
            'status': 'ok',
            'service': 'easystreamapi',
            'version': '1.0.0',
          }),
          200,
        );
      }

      if (req.url.path == '/discover') {
        final category = req.url.queryParameters['category'] ?? 'trending';
        return http.Response(
          json.encode([
            {
              'id': category == 'anime' ? 127532 : (category == 'movies' ? 872585 : 1396),
              'kind': category == 'movies' ? 'movie' : 'tv',
              'is_anime': category == 'anime',
              'title': switch (category) {
                'trending' => 'Trending Show',
                'movies' => 'Oppenheimer',
                'tv' => 'Breaking Bad',
                'anime' => 'Solo Leveling',
                _ => 'Catalog Item',
              },
              'year': '2024',
            },
          ]),
          200,
        );
      }

      if (req.url.path == '/search') {
        searchQueries.add(req.url.query);
        final type = req.url.queryParameters['type'] ?? 'all';
        return http.Response(
          json.encode([
            {
              'id': 1396,
              'kind': type == 'movie' ? 'movie' : 'tv',
              'is_anime': type == 'anime',
              'title': 'Breaking Bad ($type)',
              'year': '2008',
            },
          ]),
          200,
        );
      }

      if (req.url.path == '/media/tv/1396') {
        return http.Response(
          json.encode({
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': 'Breaking Bad',
            'overview': 'Un professore di chimica inizia una nuova vita.',
            'year': '2008',
            'rating': 8.9,
            'runtime': 47,
            'genres': ['Dramma', 'Crime'],
            'seasons': [
              {
                'season_number': 1,
                'name': 'Stagione 1',
                'episode_count': 7,
              },
              {
                'season_number': 2,
                'name': 'Stagione 2',
                'episode_count': 13,
              },
            ],
          }),
          200,
        );
      }

      if (req.url.path == '/media/tv/1396/season/1') {
        return http.Response(
          json.encode({
            'season_number': 1,
            'name': 'Stagione 1',
            'episodes': [
              {
                'episode_number': 1,
                'name': 'Questione di chimica',
                'overview': 'Primo episodio.',
                'runtime': 58,
                'watched': false,
              },
              {
                'episode_number': 2,
                'name': 'Senza ritorno',
                'overview': 'Secondo episodio.',
                'runtime': 48,
                'watched': true,
              },
            ],
          }),
          200,
        );
      }

      if (req.url.path == '/media/tv/1396/season/2') {
        return http.Response(
          json.encode({
            'season_number': 2,
            'name': 'Stagione 2',
            'episodes': [
              {
                'episode_number': 1,
                'name': 'Settecento trentasette',
                'runtime': 47,
                'watched': false,
              },
            ],
          }),
          200,
        );
      }

      if (req.url.path == '/stream/resolve/tv/1396') {
        resolveQueries.add(req.url.query);
        final source = req.url.queryParameters['source'] ?? 'auto';
        final episode = int.tryParse(req.url.queryParameters['episode'] ?? '1') ?? 1;
        final lang = req.url.queryParameters['lang'] ?? 'it';
        final quality = req.url.queryParameters['quality'] ?? 'auto';

        final useTorrent = source == 'torrent';
        return http.Response(
          json.encode({
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': 'Breaking Bad',
            'season': 1,
            'episode': episode,
            'recommended_mode': useTorrent ? 'torrent' : 'hls',
            'recommended_url': useTorrent
                ? '/stream/torrent/hash_ep_$episode?file_idx=0'
                : 'https://cdn.example.com/s1e${episode}_${lang}_$quality.m3u8',
            'recommended_info_hash': useTorrent ? 'hash_ep_$episode' : null,
            'hls': {
              'source': 'vixsrc',
              'playlist_url':
                  'https://cdn.example.com/s1e${episode}_${lang}_$quality.m3u8',
              'referer': 'https://vixsrc.to/',
              'audio': [
                {
                  'language': 'en',
                  'name': 'English (External)',
                  'url': 'https://cdn.example.com/audio_en.m3u8',
                },
              ],
              'subtitles': [
                {
                  'language': 'it',
                  'name': 'Italiano (External)',
                  'url': 'https://cdn.example.com/sub_it.vtt',
                },
              ],
              'video': [],
            },
            'torrents': [
              {
                'title': 'Breaking.Bad.S01E0$episode.1080p.ITA.mkv',
                'info_hash': 'hash_ep_$episode',
                'magnet': 'magnet:?xt=urn:btih:hash_ep_$episode',
                'quality': '1080p',
                'seeders': 350,
                'size_bytes': 1500000000,
                'file_idx': 0,
                'languages': ['ita'],
                'cached': true,
                'stream_url': '/stream/torrent/hash_ep_$episode?file_idx=0',
              },
            ],
            'next_episode': {
              'season': 1,
              'episode': episode + 1,
              'name': 'Episodio ${episode + 1}',
            },
          }),
          200,
        );
      }

      if (req.method == 'DELETE' && req.url.path.startsWith('/torrents/')) {
        deletedTorrentHashes.add(req.url.path.replaceFirst('/torrents/', ''));
        return http.Response(json.encode({'status': 'stopped'}), 200);
      }

      if (req.url.path == '/library') {
        return http.Response(
          json.encode({
            'continue_watching': [
              {
                'id': 1396,
                'kind': 'tv',
                'is_anime': false,
                'title': 'Breaking Bad',
                'year': '2008',
                'status': 'watching',
                'current_season': 1,
                'current_episode': 4,
                'position_secs': 450,
                'duration_secs': 2700,
                'watched_episodes': ['S1E1', 'S1E2', 'S1E3'],
                'updated_at': '2026-11-23T12:00:00Z',
                'has_new_episodes': true,
                'new_episodes_count': 1,
              },
            ],
            'saved': [
              {
                'id': 872585,
                'kind': 'movie',
                'is_anime': false,
                'title': 'Oppenheimer',
                'year': '2023',
                'status': 'saved',
                'position_secs': 0,
                'duration_secs': 0,
                'watched_episodes': [],
                'updated_at': '2026-11-23T11:00:00Z',
                'has_new_episodes': false,
                'new_episodes_count': 0,
              },
            ],
            'completed': [
              {
                'id': 550,
                'kind': 'movie',
                'is_anime': false,
                'title': 'Fight Club',
                'year': '1999',
                'status': 'completed',
                'position_secs': 8000,
                'duration_secs': 8000,
                'watched_episodes': [],
                'updated_at': '2026-11-22T10:00:00Z',
                'has_new_episodes': false,
                'new_episodes_count': 0,
              },
            ],
            'items': [
              {
                'id': 1396,
                'kind': 'tv',
                'is_anime': false,
                'title': 'Breaking Bad',
                'year': '2008',
                'status': 'watching',
                'current_season': 1,
                'current_episode': 4,
                'position_secs': 450,
                'duration_secs': 2700,
                'watched_episodes': ['S1E1', 'S1E2', 'S1E3'],
                'updated_at': '2026-11-23T12:00:00Z',
                'has_new_episodes': true,
                'new_episodes_count': 1,
              },
              {
                'id': 872585,
                'kind': 'movie',
                'is_anime': false,
                'title': 'Oppenheimer',
                'year': '2023',
                'status': 'saved',
                'position_secs': 0,
                'duration_secs': 0,
                'watched_episodes': [],
                'updated_at': '2026-11-23T11:00:00Z',
                'has_new_episodes': false,
                'new_episodes_count': 0,
              },
              {
                'id': 550,
                'kind': 'movie',
                'is_anime': false,
                'title': 'Fight Club',
                'year': '1999',
                'status': 'completed',
                'position_secs': 8000,
                'duration_secs': 8000,
                'watched_episodes': [],
                'updated_at': '2026-11-22T10:00:00Z',
                'has_new_episodes': false,
                'new_episodes_count': 0,
              },
            ],
          }),
          200,
        );
      }

      if (req.url.path == '/library/tv/1396/watched') {
        final payload = json.decode(req.body) as Map<String, dynamic>;
        watchedPayloads.add(payload);
        return http.Response(
          json.encode({
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': 'Breaking Bad',
            'status': 'watching',
            'current_season': 1,
            'current_episode': 1,
            'position_secs': 450,
            'duration_secs': 2700,
            'watched_episodes':
                payload['watched'] == true ? ['S1E1'] : <String>[],
            'updated_at': '2026-11-23T12:10:00Z',
            'has_new_episodes': false,
            'new_episodes_count': 0,
          }),
          200,
        );
      }

      if (req.url.path.startsWith('/library/tv/1396/progress')) {
        return http.Response(
          json.encode({
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': 'Breaking Bad',
            'status': 'watching',
            'current_season': 1,
            'current_episode': 1,
            'position_secs': 100,
            'duration_secs': 2700,
            'watched_episodes': [],
            'updated_at': '2026-11-23T12:10:00Z',
            'has_new_episodes': false,
            'new_episodes_count': 0,
          }),
          200,
        );
      }

      if (req.method == 'PUT' && req.url.path.startsWith('/library/')) {
        return http.Response(
          json.encode({
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': 'Breaking Bad',
            'status': 'saved',
            'position_secs': 0,
            'duration_secs': 0,
            'watched_episodes': [],
            'updated_at': '2026-11-23T12:10:00Z',
            'has_new_episodes': false,
            'new_episodes_count': 0,
          }),
          200,
        );
      }

      if (req.method == 'DELETE' && req.url.path.startsWith('/library/')) {
        return http.Response(json.encode({'deleted': true}), 200);
      }

      return http.Response('Not Found', 404);
    });

    config = ConfigService(
      httpClient: client,
      isAndroidOverride: isAndroid,
      persist: false,
    );
    await config.init(checkHealthOnInit: true);
    api = ApiClient(config: config, httpClient: client);
    library = LibraryService(
      apiClient: api,
      configService: config,
      persist: false,
    );
    await library.init(syncOnInit: false);
    torrentGuard = TorrentSessionGuard(apiClient: api);
  }

  Future<void> dispose() async {}
}

void main() {
  testWidgets('AppShell renders mobile NavigationBar, desktop NavigationRail, and switches tabs', (
    tester,
  ) async {
    final harness = _TestHarness();
    await harness.init();
    addTearDown(harness.dispose);

    // Narrow viewport -> NavigationBar
    tester.view.physicalSize = const Size(420, 840);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      OnlyStreamApp(
        apiClient: harness.api,
        configService: harness.config,
        libraryService: harness.library,
        torrentGuard: harness.torrentGuard,
        playerFactory: FakePlayerAdapter.new,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Continua a guardare'), findsOneWidget);
    expect(find.text('Nuovi episodi'), findsOneWidget);
    expect(find.text('In tendenza'), findsOneWidget);
    expect(find.textContaining('S1 · E4'), findsWidgets);

    // Switch to Cerca
    await tester.tap(find.text('Cerca').last);
    await tester.pumpAndSettle();
    expect(find.text('Digita un titolo per cercare nel catalogo.'), findsOneWidget);

    // Switch to Libreria
    await tester.tap(find.text('Libreria').last);
    await tester.pumpAndSettle();
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('Salvati'), findsOneWidget);
    expect(find.text('Completati'), findsOneWidget);

    // Wide viewport -> NavigationRail
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('SearchScreen filters and debounced search render poster grid', (
    tester,
  ) async {
    final harness = _TestHarness();
    await harness.init();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AppShell(
          apiClient: harness.api,
          configService: harness.config,
          libraryService: harness.library,
          loadHomeOnInit: false,
          initialIndex: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Breaking');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(harness.searchQueries.last, contains('type=all'));
    expect(find.text('Breaking Bad (all)'), findsOneWidget);

    await tester.tap(find.text('Anime'));
    await tester.pumpAndSettle();
    expect(harness.searchQueries.last, contains('type=anime'));
    expect(find.text('Breaking Bad (anime)'), findsOneWidget);
  });

  testWidgets('LibraryScreen switches segments and removes item', (tester) async {
    final harness = _TestHarness();
    await harness.init();
    await harness.library.refresh();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AppShell(
          apiClient: harness.api,
          configService: harness.config,
          libraryService: harness.library,
          loadHomeOnInit: false,
          initialIndex: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('Nuovi episodi (1)'), findsOneWidget);

    await tester.tap(find.text('Salvati'));
    await tester.pumpAndSettle();
    expect(find.text('Oppenheimer'), findsOneWidget);

    await tester.tap(find.text('Completati'));
    await tester.pumpAndSettle();
    expect(find.text('Fight Club'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();
    expect(find.text('Fight Club'), findsNothing);
  });

  testWidgets('MediaDetailScreen loads episodes, toggles watched, and shows Torrent options', (
    tester,
  ) async {
    final harness = _TestHarness();
    await harness.init();
    addTearDown(harness.dispose);

    Uri? launchedMagnet;
    final fakePlayer = FakePlayerAdapter();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaDetailScreen(
          summary: const MediaSummary(
            id: 1396,
            kind: MediaKind.tv,
            title: 'Breaking Bad',
            year: '2008',
          ),
          apiClient: harness.api,
          configService: harness.config,
          libraryService: harness.library,
          torrentGuard: harness.torrentGuard,
          playerFactory: () => fakePlayer,
          urlLauncher: (uri) async {
            launchedMagnet = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('E1 · Questione di chimica'), findsOneWidget);

    // Toggle episode 1 watched
    await tester.tap(find.byTooltip('Segna come visto').first);
    await tester.pumpAndSettle();
    expect(harness.watchedPayloads, isNotEmpty);
    expect(harness.watchedPayloads.last['watched'], isTrue);

    // Switch season to Stagione 2
    await tester.tap(find.text('Stagione 2'));
    await tester.pumpAndSettle();
    expect(find.text('E1 · Settecento trentasette'), findsOneWidget);

    // Switch source to Torrent
    await tester.tap(find.text('Torrent'));
    await tester.pumpAndSettle();
    expect(find.text('Breaking.Bad.S01E01.1080p.ITA.mkv'), findsOneWidget);

    // Magnet button calls launcher
    await tester.tap(find.byTooltip('Apri magnet link').first);
    await tester.pumpAndSettle();
    expect(launchedMagnet?.scheme, 'magnet');

    // Tapping torrent row opens VideoPlayerScreen with TorrentSessionGuard active
    await tester.tap(find.text('Breaking.Bad.S01E01.1080p.ITA.mkv'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake_video_surface')), findsOneWidget);
    expect(harness.torrentGuard.activeInfoHash, 'hash_ep_1');
    expect(
      fakePlayer.openCalls.single.url,
      'http://localhost:5555/stream/torrent/hash_ep_1?file_idx=0',
    );
  });

  testWidgets(
    'VideoPlayerScreen passes Referer header, switches Language/Quality/Source, stops torrent on switch/next/dispose',
    (tester) async {
      final harness = _TestHarness();
      await harness.init();
      addTearDown(harness.dispose);

      late FakePlayerAdapter fakePlayer;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: VideoPlayerScreen(
            media: const MediaSummary(
              id: 1396,
              kind: MediaKind.tv,
              title: 'Breaking Bad',
            ),
            season: 1,
            episode: 1,
            initialLanguage: 'it',
            initialQuality: 'auto',
            initialSource: 'hls',
            apiClient: harness.api,
            configService: harness.config,
            libraryService: harness.library,
            torrentGuard: harness.torrentGuard,
            playerFactory: () {
              fakePlayer = FakePlayerAdapter();
              return fakePlayer;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial HLS open passes Referer header from resolved.hls.referer
      expect(fakePlayer.openCalls.length, 1);
      expect(
        fakePlayer.openCalls.first.url,
        'https://cdn.example.com/s1e1_it_auto.m3u8',
      );
      expect(
        fakePlayer.openCalls.first.httpHeaders,
        {'Referer': 'https://vixsrc.to/'},
      );

      // Emit player tracks and test Audio & Subtitles dialogs
      fakePlayer.audioTracksCtrl.add([
        const PlayerTrackItem(id: '1', title: 'Italiano', language: 'it'),
      ]);
      fakePlayer.subtitleTracksCtrl.add([
        const PlayerTrackItem(id: '2', title: 'Italiano', language: 'it'),
      ]);
      await tester.pump();

      await tester.tap(find.byTooltip('Audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English (External)'));
      await tester.pumpAndSettle();
      expect(fakePlayer.selectedAudioTracks.single.isExternal, isTrue);

      await tester.tap(find.byTooltip('Sottotitoli'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disattiva'));
      await tester.pumpAndSettle();
      expect(fakePlayer.selectedSubtitleTracks.single, isNull);

      // Switch Language IT -> EN
      await tester.tap(find.textContaining('Opzioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(harness.resolveQueries.last, contains('lang=en'));

      // Switch Quality Auto -> 720p
      await tester.tap(find.textContaining('Opzioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(harness.resolveQueries.last, contains('quality=720p'));

      // Switch Source HLS -> Torrent
      await tester.tap(find.textContaining('Opzioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Torrent'));
      await tester.pumpAndSettle();
      expect(harness.torrentGuard.activeInfoHash, 'hash_ep_1');
      expect(
        fakePlayer.openCalls.last.url,
        'http://localhost:5555/stream/torrent/hash_ep_1?file_idx=0',
      );

      // Next episode stops active torrent hash_ep_1 and starts hash_ep_2
      await tester.tap(find.text('Prossimo episodio'));
      await tester.pumpAndSettle();
      expect(harness.deletedTorrentHashes, contains('hash_ep_1'));
      expect(harness.torrentGuard.activeInfoHash, 'hash_ep_2');

      // Switch Torrent -> HLS stops hash_ep_2
      await tester.tap(find.textContaining('Opzioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HLS'));
      await tester.pumpAndSettle();
      expect(harness.deletedTorrentHashes, ['hash_ep_1', 'hash_ep_2']);
      expect(harness.torrentGuard.hasActiveTorrent, isFalse);

      // Switch back to Torrent then test dispose() stops active torrent
      await tester.tap(find.textContaining('Opzioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Torrent'));
      await tester.pumpAndSettle();
      expect(harness.torrentGuard.activeInfoHash, 'hash_ep_2');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(harness.deletedTorrentHashes, ['hash_ep_1', 'hash_ep_2', 'hash_ep_2']);
      expect(fakePlayer.disposed, isTrue);
    },
  );

  testWidgets('VideoPlayerScreen stops active torrent on detached and >15s paused', (
    tester,
  ) async {
    final harness = _TestHarness();
    await harness.init();
    addTearDown(harness.dispose);

    late FakePlayerAdapter fakePlayer;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: VideoPlayerScreen(
          media: const MediaSummary(
            id: 1396,
            kind: MediaKind.tv,
            title: 'Breaking Bad',
          ),
          season: 1,
          episode: 1,
          initialSource: 'torrent',
          apiClient: harness.api,
          configService: harness.config,
          libraryService: harness.library,
          torrentGuard: harness.torrentGuard,
          playerFactory: () {
            fakePlayer = FakePlayerAdapter();
            return fakePlayer;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.torrentGuard.activeInfoHash, 'hash_ep_1');

    // Simulate paused playback in background for >15s
    await fakePlayer.pause();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 16));
    expect(harness.deletedTorrentHashes, ['hash_ep_1']);
    expect(harness.torrentGuard.hasActiveTorrent, isFalse);

    // Re-activate torrent and verify AppLifecycleState.detached stops immediately
    await harness.torrentGuard.activateTorrent('hash_ep_2');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(harness.deletedTorrentHashes, ['hash_ep_1', 'hash_ep_2']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('HomeScreen shows calm offline banner with Android companion start and SettingsScreen updates prefs', (
    tester,
  ) async {
    const channel = MethodChannel('com.loriek.onlystream/companion_widget');
    final companionCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      companionCalls.add(call.method);
      return true;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final offlineClient = MockClient((_) async {
      throw const SocketException('Offline');
    });
    final config = ConfigService(
      httpClient: offlineClient,
      isAndroidOverride: true,
      persist: false,
      companionBridge: CompanionServerBridge(
        channel: channel,
        isAndroidOverride: true,
      ),
    );
    await config.init(checkHealthOnInit: false);
    final api = ApiClient(config: config, httpClient: offlineClient);
    final library = LibraryService(
      apiClient: api,
      configService: config,
      persist: false,
    );
    await library.init(syncOnInit: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AppShell(
          apiClient: api,
          configService: config,
          libraryService: library,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Server non raggiungibile'), findsOneWidget);
    expect(find.text('Avvia server locale'), findsOneWidget);

    await tester.tap(find.text('Avvia server locale'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(companionCalls, contains('startServer'));

    // Open SettingsScreen and change playback defaults
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SettingsScreen(configService: config),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remoto'));
    await tester.pumpAndSettle();
    expect(find.text('Preset salvati'), findsOneWidget);
    expect(config.language, 'en');
    expect(config.quality, '1080p');
    expect(config.serverMode, 'remote');
  });

  testWidgets(
    'VideoPlayerScreen audio and subtitle dialogs scroll cleanly in landscape',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = _TestHarness();
      await harness.init();

      final fakePlayer = FakePlayerAdapter();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: VideoPlayerScreen(
            media: const MediaSummary(
              id: 1396,
              kind: MediaKind.tv,
              isAnime: false,
              title: 'Breaking Bad',
            ),
            apiClient: harness.api,
            configService: harness.config,
            libraryService: harness.library,
            torrentGuard: harness.torrentGuard,
            playerFactory: () => fakePlayer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final manyAudio = List.generate(
        25,
        (i) => PlayerTrackItem(id: 'a$i', title: 'Audio Track $i', language: 'it'),
      );
      final manySubs = List.generate(
        25,
        (i) => PlayerTrackItem(id: 's$i', title: 'Subtitle Track $i', language: 'it'),
      );
      fakePlayer.audioTracksCtrl.add(manyAudio);
      fakePlayer.subtitleTracksCtrl.add(manySubs);
      await tester.pump();

      // Open Audio dialog & scroll to bottom track
      await tester.tap(find.byTooltip('Audio'));
      await tester.pumpAndSettle();
      expect(find.text('Tracce audio'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Audio Track 24'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Audio Track 24'));
      await tester.pumpAndSettle();
      expect(fakePlayer.selectedAudioTracks.last.id, 'a24');

      // Open Subtitles dialog & scroll to bottom track
      await tester.tap(find.byTooltip('Sottotitoli'));
      await tester.pumpAndSettle();
      expect(find.text('Sottotitoli'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Subtitle Track 24'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Subtitle Track 24'));
      await tester.pumpAndSettle();
      expect(fakePlayer.selectedSubtitleTracks.last?.id, 's24');
    },
  );
}
