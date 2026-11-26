import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:onlystream/services/desktop_window_controller.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/desktop_window_frame.dart';

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
  final bufferCtrl = StreamController<Duration>.broadcast();
  final volumeCtrl = StreamController<double>.broadcast();
  final rateCtrl = StreamController<double>.broadcast();
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
  final List<double> setVolumes = [];
  final List<double> setRates = [];
  final List<Duration> seeks = [];
  bool disposed = false;
  bool paused = false;
  BoxFit lastFit = BoxFit.contain;

  @override
  Stream<bool> get playingStream => playingCtrl.stream;
  @override
  Stream<bool> get bufferingStream => bufferingCtrl.stream;
  @override
  Stream<Duration> get positionStream => positionCtrl.stream;
  @override
  Stream<Duration> get durationStream => durationCtrl.stream;
  @override
  Stream<Duration> get bufferStream => bufferCtrl.stream;
  @override
  Stream<double> get volumeStream => volumeCtrl.stream;
  @override
  Stream<double> get rateStream => rateCtrl.stream;
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
    paused = false;
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
    seeks.add(position);
    positionCtrl.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 100.0);
    setVolumes.add(clamped);
    volumeCtrl.add(clamped);
  }

  @override
  Future<void> setRate(double rate) async {
    final clamped = rate.clamp(0.25, 4.0);
    setRates.add(clamped);
    rateCtrl.add(clamped);
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
  Widget buildVideoView(BuildContext context, {BoxFit fit = BoxFit.contain}) {
    lastFit = fit;
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
      bufferCtrl.close(),
      volumeCtrl.close(),
      rateCtrl.close(),
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

  testWidgets('SettingsScreen loads and updates custom provider base URLs', (
    WidgetTester tester,
  ) async {
    Map<String, dynamic>? savedPatch;
    final mockClient = MockClient((req) async {
      if (req.url.path == '/config/sources' && req.method == 'GET') {
        return http.Response(
          json.encode({
            'sources': {
              'vixsrc_url': 'https://vixsrc.to',
              'streamingunity_url': 'https://streamingunity.day',
              'guardaserie_url': 'https://guardaseriex.help',
              'animeunity_url': 'https://animeunity.cx',
              'animeworld_url': 'https://www.animeworld.ac',
              'corsaro_url': 'https://icv.stremio-italia.eu',
              'torrentio_url': 'https://torrentio.strem.fun',
            },
            'defaults': {
              'vixsrc_url': 'https://vixsrc.to',
              'streamingunity_url': 'https://streamingunity.day',
              'guardaserie_url': 'https://guardaseriex.help',
              'animeunity_url': 'https://animeunity.cx',
              'animeworld_url': 'https://www.animeworld.ac',
              'corsaro_url': 'https://icv.stremio-italia.eu',
              'torrentio_url': 'https://torrentio.strem.fun',
            },
          }),
          200,
        );
      }
      if (req.url.path == '/config/sources' && req.method == 'PUT') {
        savedPatch = json.decode(req.body) as Map<String, dynamic>;
        return http.Response(
          json.encode({
            'sources': savedPatch,
            'defaults': {
              'vixsrc_url': 'https://vixsrc.to',
              'streamingunity_url': 'https://streamingunity.day',
              'guardaserie_url': 'https://guardaseriex.help',
              'animeunity_url': 'https://animeunity.cx',
              'animeworld_url': 'https://www.animeworld.ac',
              'corsaro_url': 'https://icv.stremio-italia.eu',
              'torrentio_url': 'https://torrentio.strem.fun',
            },
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    final config = ConfigService(httpClient: mockClient, persist: false);
    await config.init(checkHealthOnInit: false);
    final api = ApiClient(config: config, httpClient: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SettingsScreen(configService: config, apiClient: api),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'VixSrc'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'VixSrc'),
      'https://vixsrc.custom.example',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'StreamingUnity'),
      'https://streamingunity.custom.example',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'GuardaSerie'),
      'https://guardaserie.custom.example',
    );
    await tester.scrollUntilVisible(
      find.text('Salva link'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Salva link'));
    await tester.pumpAndSettle();

    expect(savedPatch?['vixsrc_url'], 'https://vixsrc.custom.example');
    expect(
      savedPatch?['streamingunity_url'],
      'https://streamingunity.custom.example',
    );
    expect(
      savedPatch?['guardaserie_url'],
      'https://guardaserie.custom.example',
    );
    expect(find.text('Link base salvati sul server'), findsOneWidget);
  });

  testWidgets(
    'VideoPlayerScreen aligns spinner concentrically on Play/Pause, auto-hides in 3s, toggles Zoom/Fit, and fits S23 portrait without overflow',
    (WidgetTester tester) async {
      // Galaxy S23 portrait dimensions
      tester.view.physicalSize = const Size(360, 800);
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
              title: 'Breaking Bad',
            ),
            season: 1,
            episode: 1,
            apiClient: harness.api,
            configService: harness.config,
            libraryService: harness.library,
            torrentGuard: harness.torrentGuard,
            playerFactory: () => fakePlayer,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Trigger buffering so both Play/Pause and CircularProgressIndicator are shown
      fakePlayer.bufferingCtrl.add(true);
      await tester.pump();
      await tester.pump();

      final playCenter = tester.getCenter(
        find.byKey(const Key('player_play_pause_button')),
      );
      final spinnerCenter = tester.getCenter(
        find.byKey(const Key('player_loading_indicator')),
      );
      expect((playCenter.dx - spinnerCenter.dx).abs(), lessThan(0.5));
      expect((playCenter.dy - spinnerCenter.dy).abs(), lessThan(0.5));

      fakePlayer.bufferingCtrl.add(false);
      await tester.pump();
      await tester.pump();

      // Zoom/Fit toggle cycles contain <-> cover
      expect(fakePlayer.lastFit, BoxFit.contain);
      await tester.tap(find.byKey(const Key('player_zoom_fit_button')));
      await tester.pump();
      expect(fakePlayer.lastFit, BoxFit.cover);
      await tester.tap(find.byKey(const Key('player_zoom_fit_button')));
      await tester.pump();
      expect(fakePlayer.lastFit, BoxFit.contain);

      // Cast button is present in top bar
      expect(find.byKey(const Key('player_cast_button')), findsOneWidget);

      // Auto-hide after 3 seconds
      double overlayOpacity() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
      expect(overlayOpacity(), 1.0);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      expect(overlayOpacity(), 0.0);

      // Tap when hidden shows controls and schedules 3s auto-hide
      await tester.tapAt(const Offset(180, 220));
      await tester.pump(const Duration(milliseconds: 250));
      expect(overlayOpacity(), 1.0);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      expect(overlayOpacity(), 0.0);

      // Tap when visible on empty area immediately hides controls
      await tester.tapAt(const Offset(180, 220));
      await tester.pump(const Duration(milliseconds: 250));
      expect(overlayOpacity(), 1.0);
      await tester.tapAt(const Offset(180, 220));
      await tester.pump(const Duration(milliseconds: 250));
      expect(overlayOpacity(), 0.0);
    },
  );

  testWidgets(
    'Per-episode positions persist locally in LibraryService and auto-resume in VideoPlayerScreen',
    (WidgetTester tester) async {
      late Directory tempDir;
      late _TestHarness harness;
      late LibraryService reloadedLib;

      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('onlystream_ep_');
        harness = _TestHarness();
        await harness.init();

        final persistedLib = LibraryService(
          apiClient: harness.api,
          configService: harness.config,
          storageDirOverride: tempDir,
          persist: true,
        );
        await persistedLib.init(syncOnInit: false);

        await persistedLib.reportProgress(
          kind: MediaKind.tv,
          id: 1396,
          isAnime: false,
          title: 'Breaking Bad',
          season: 1,
          episode: 1,
          positionSecs: 320,
          durationSecs: 2400,
        );
        await persistedLib.reportProgress(
          kind: MediaKind.tv,
          id: 1396,
          isAnime: false,
          title: 'Breaking Bad',
          season: 1,
          episode: 2,
          positionSecs: 900,
          durationSecs: 2500,
        );
        // Allow unawaited _saveCache() to flush to disk
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Reload from disk into a fresh LibraryService instance
        reloadedLib = LibraryService(
          apiClient: harness.api,
          configService: harness.config,
          storageDirOverride: tempDir,
          persist: true,
        );
        await reloadedLib.init(syncOnInit: false);
      });
      addTearDown(() async {
        await tester.runAsync(() => tempDir.delete(recursive: true));
      });

      expect(reloadedLib.episodePositionSecs(MediaKind.tv, 1396, 1, 1), 320);
      expect(reloadedLib.episodePositionSecs(MediaKind.tv, 1396, 1, 2), 900);

      // Opening S1E2 directly in VideoPlayerScreen auto-resumes at 900s
      final fakePlayer = FakePlayerAdapter();
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
            episode: 2,
            apiClient: harness.api,
            configService: harness.config,
            libraryService: reloadedLib,
            torrentGuard: harness.torrentGuard,
            playerFactory: () => fakePlayer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlayer.openCalls.single.start, const Duration(seconds: 900));
    },
  );

  testWidgets(
    'VideoPlayerScreen hides fullscreen/maximize on Android and iOS while keeping other controls and mobile volume',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const companionChannel = MethodChannel('com.loriek.onlystream/companion');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(companionChannel, (_) async => false);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(companionChannel, null),
      );

      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final harness = _TestHarness();
        await harness.init(isAndroid: platform == TargetPlatform.android);
        final fakePlayer = FakePlayerAdapter();

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
              apiClient: harness.api,
              configService: harness.config,
              libraryService: harness.library,
              torrentGuard: harness.torrentGuard,
              playerFactory: () => fakePlayer,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('player_fullscreen_button')), findsNothing);
        expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
        expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);

        expect(find.byKey(const Key('player_cast_button')), findsOneWidget);
        expect(find.byKey(const Key('player_zoom_fit_button')), findsOneWidget);
        expect(find.byTooltip('Audio'), findsOneWidget);
        expect(find.byTooltip('Sottotitoli'), findsOneWidget);
        expect(find.byKey(const Key('player_volume_button')), findsOneWidget);
        expect(find.byKey(const Key('player_speed_button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('player_volume_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('player_volume_slider')), findsOneWidget);
        expect(find.byKey(const Key('player_mute_button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('player_mute_button')));
        await tester.pumpAndSettle();
        expect(fakePlayer.setVolumes.last, 0.0);
        expect(harness.config.playerVolume, 0.0);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'DesktopWindowFrame renders custom titlebar on desktop, forwards caption actions, hides in fullscreen, and skips mobile',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const channel = MethodChannel('com.loriek.onlystream/window_test');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'getWindowState') {
          return {
            'isMaximized': false,
            'isFullscreen': false,
            'isFocused': true,
          };
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final windowController = DesktopWindowController(
        channel: channel,
        isSupportedOverride: true,
      );
      await windowController.init();
      addTearDown(windowController.dispose);

      final harness = _TestHarness();
      await harness.init();
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        OnlyStreamApp(
          apiClient: harness.api,
          configService: harness.config,
          libraryService: harness.library,
          torrentGuard: harness.torrentGuard,
          playerFactory: FakePlayerAdapter.new,
          windowController: windowController,
          loadHomeOnInit: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('desktop_window_titlebar')), findsOneWidget);
      expect(find.byKey(const Key('window_minimize_button')), findsOneWidget);
      expect(find.byKey(const Key('window_maximize_button')), findsOneWidget);
      expect(find.byKey(const Key('window_close_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('window_minimize_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('window_maximize_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('window_maximize_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('window_close_button')));
      await tester.pump();

      expect(calls, [
        'getWindowState',
        'minimize',
        'maximize',
        'unmaximize',
        'close',
      ]);

      // Simulate native fullscreen state transition hiding the titlebar
      final encoded = channel.codec.encodeMethodCall(
        const MethodCall('onWindowStateChanged', {
          'isMaximized': false,
          'isFullscreen': true,
          'isFocused': true,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, encoded, (_) {});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop_window_titlebar')), findsNothing);

      // Mobile / unsupported platform does not render custom desktop titlebar
      final mobileController = DesktopWindowController(
        isSupportedOverride: false,
      );
      addTearDown(mobileController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DesktopWindowFrame(
            controller: mobileController,
            child: const Scaffold(body: Text('Mobile Body')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop_window_titlebar')), findsNothing);
      expect(find.text('Mobile Body'), findsOneWidget);
    },
  );

  testWidgets(
    'Desktop VideoPlayerScreen provides inline volume, speed, fullscreen, and keyboard shortcuts',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const channel = MethodChannel('com.loriek.onlystream/window_player_test');
      final windowCalls = <(String, dynamic)>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        windowCalls.add((call.method, call.arguments));
        if (call.method == 'getWindowState') {
          return {
            'isMaximized': false,
            'isFullscreen': false,
            'isFocused': true,
          };
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final windowController = DesktopWindowController(
        channel: channel,
        isSupportedOverride: true,
      );
      await windowController.init();
      addTearDown(windowController.dispose);

      final harness = _TestHarness();
      await harness.init();
      addTearDown(harness.dispose);
      final fakePlayer = FakePlayerAdapter();

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
            apiClient: harness.api,
            configService: harness.config,
            libraryService: harness.library,
            torrentGuard: harness.torrentGuard,
            playerFactory: () => fakePlayer,
            windowController: windowController,
            isDesktopOverride: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('player_fullscreen_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('desktop_play_pause_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('player_mute_button')), findsOneWidget);
      expect(find.byKey(const Key('player_volume_slider')), findsOneWidget);
      expect(find.byKey(const Key('player_volume_label')), findsOneWidget);
      expect(find.byKey(const Key('player_speed_button')), findsOneWidget);
      expect(find.byKey(const Key('player_shortcuts_button')), findsOneWidget);

      // Mute and unmute via bottom dock button
      await tester.tap(find.byKey(const Key('player_mute_button')));
      await tester.pumpAndSettle();
      expect(fakePlayer.setVolumes.last, 0.0);
      expect(harness.config.playerVolume, 0.0);
      expect(find.text('0%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('player_mute_button')));
      await tester.pumpAndSettle();
      expect(fakePlayer.setVolumes.last, 100.0);
      expect(harness.config.playerVolume, 100.0);
      expect(find.text('100%'), findsOneWidget);

      // Drag volume slider to adjust volume and persist
      await tester.drag(
        find.byKey(const Key('player_volume_slider')),
        const Offset(-36, 0),
      );
      await tester.pumpAndSettle();
      expect(fakePlayer.setVolumes.last, lessThan(100.0));
      expect(harness.config.playerVolume, lessThan(100.0));

      // Change playback speed to 1.5x
      await tester.tap(find.byKey(const Key('player_speed_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(fakePlayer.setRates.last, 1.5);

      // Keyboard shortcuts: Space, ArrowRight, ArrowLeft, ArrowUp, ArrowDown, M, Z, F
      final wasPaused = fakePlayer.paused;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fakePlayer.paused, !wasPaused);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final afterForward = fakePlayer.seeks.last;
      expect(afterForward, const Duration(seconds: 10));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(fakePlayer.seeks.last, Duration.zero);

      final volBeforeUp = fakePlayer.setVolumes.last;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 300));
      expect(fakePlayer.setVolumes.last, closeTo(volBeforeUp + 5.0, 0.1));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 300));
      expect(fakePlayer.setVolumes.last, closeTo(volBeforeUp, 0.1));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(fakePlayer.setVolumes.last, 0.0);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(fakePlayer.setVolumes.last, greaterThan(0.0));

      expect(fakePlayer.lastFit, BoxFit.contain);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(fakePlayer.lastFit, BoxFit.cover);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(
        windowCalls,
        contains(('setFullscreen', true)),
      );

      // Disposing player while fullscreen exits fullscreen automatically
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        windowCalls,
        contains(('setFullscreen', false)),
      );
    },
  );
}
