import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onlystream/models/library.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/models/server.dart';
import 'package:onlystream/services/api_client.dart';

void main() {
  group('Models JSON parsing', () {
    test('MediaSummary parses movie, tv, anime, and flexible year types', () {
      final anime = MediaSummary.fromJson({
        'id': 127532,
        'kind': 'tv',
        'is_anime': true,
        'title': 'Solo Leveling',
        'original_title': '俺だけレベルアップな件',
        'overview': 'A weak hunter gains a leveling system.',
        'year': 2024,
        'rating': 8.6,
        'poster': 'https://image.tmdb.org/t/p/w500/poster.jpg',
        'backdrop': 'https://image.tmdb.org/t/p/w1280/backdrop.jpg',
      });

      expect(anime.id, 127532);
      expect(anime.kind, MediaKind.tv);
      expect(anime.isAnime, isTrue);
      expect(anime.kindLabel, 'Anime');
      expect(anime.year, '2024');
      expect(anime.rating, 8.6);

      final movie = MediaSummary.fromJson({
        'id': 872585,
        'kind': 'movie',
        'is_anime': false,
        'title': 'Oppenheimer',
        'year': '2023',
      });
      expect(movie.kind, MediaKind.movie);
      expect(movie.kindLabel, 'Film');
      expect(movie.year, '2023');
    });

    test('MediaDetail and SeasonDetail parse seasons, episodes, and library', () {
      final detail = MediaDetail.fromJson({
        'id': 1396,
        'kind': 'tv',
        'is_anime': false,
        'title': 'Breaking Bad',
        'year': '2008',
        'rating': 8.9,
        'status': 'Ended',
        'runtime': 47,
        'genres': ['Dramma', 'Crime'],
        'seasons': [
          {
            'season_number': 1,
            'name': 'Stagione 1',
            'episode_count': 7,
            'air_date': '2008-01-20',
          },
        ],
        'library': {
          'id': 1396,
          'kind': 'tv',
          'is_anime': false,
          'title': 'Breaking Bad',
          'status': 'watching',
          'current_season': 1,
          'current_episode': 4,
          'position_secs': 320,
          'duration_secs': 2800,
          'watched_episodes': ['S1E1', 'S1E2', 'S1E3'],
          'updated_at': '2026-11-23T12:00:00Z',
          'has_new_episodes': false,
          'new_episodes_count': 0,
        },
      });

      expect(detail.genres, ['Dramma', 'Crime']);
      expect(detail.seasons.length, 1);
      expect(detail.seasons.first.episodeCount, 7);
      expect(detail.library, isNotNull);
      expect(detail.library!.episodeLabel, 'S1 · E4');
      expect(detail.library!.isEpisodeWatched(1, 2), isTrue);
      expect(detail.library!.isEpisodeWatched(1, 4), isFalse);

      final season = SeasonDetail.fromJson({
        'season_number': 1,
        'name': 'Stagione 1',
        'episodes': [
          {
            'episode_number': 1,
            'name': 'Questione di chimica',
            'runtime': 58,
            'watched': true,
          },
        ],
      });
      expect(season.episodes.single.watched, isTrue);
      expect(season.episodes.single.runtime, 58);
    });

    test('ResolvedStream parses HLS referer, tracks, torrents, and next_episode', () {
      final resolved = ResolvedStream.fromJson({
        'id': 1396,
        'kind': 'tv',
        'is_anime': false,
        'title': 'Breaking Bad',
        'season': 1,
        'episode': 4,
        'recommended_mode': 'hls',
        'recommended_url': 'https://cdn.example.com/master.m3u8',
        'hls': {
          'source': 'vixsrc',
          'playlist_url': 'https://cdn.example.com/master.m3u8',
          'referer': 'https://vixsrc.to/',
          'audio': [
            {
              'language': 'it',
              'name': 'Italiano',
              'url': 'https://cdn.example.com/audio_it.m3u8',
            },
          ],
          'subtitles': [
            {
              'language': 'it',
              'name': 'Italiano',
              'url': 'https://cdn.example.com/sub_it.vtt',
            },
          ],
          'video': [
            {
              'quality': '1080p',
              'resolution': '1920x1080',
              'bandwidth': 5000000,
              'url': 'https://cdn.example.com/1080p.m3u8',
            },
          ],
        },
        'torrents': [
          {
            'title': 'Breaking.Bad.S01E04.1080p.ITA.ENG.mkv',
            'info_hash': '6a12ce77043c07604314f30fa62f2b17ea8d4ab9',
            'magnet':
                'magnet:?xt=urn:btih:6a12ce77043c07604314f30fa62f2b17ea8d4ab9',
            'quality': '1080p',
            'seeders': 412,
            'size_bytes': 2235550686,
            'file_idx': 0,
            'languages': ['ita', 'eng'],
            'source_indexer': 'ilcorsaroviola',
            'cached': true,
            'stream_url':
                '/stream/torrent/6a12ce77043c07604314f30fa62f2b17ea8d4ab9?file_idx=0',
          },
        ],
        'next_episode': {
          'season': 1,
          'episode': 5,
          'name': 'Materia grigia',
        },
      });

      expect(resolved.recommendedMode, 'hls');
      expect(resolved.hls?.referer, 'https://vixsrc.to/');
      expect(resolved.hls?.audio.single.language, 'it');
      expect(resolved.hls?.subtitles.single.url, contains('sub_it.vtt'));
      expect(resolved.torrents.single.formattedSize, '2.08 GB');
      expect(resolved.torrents.single.cached, isTrue);
      expect(resolved.nextEpisode?.shortCode, 'S1 · E5');
    });

    test('LibrarySnapshot and HealthStatus parse cleanly', () {
      final snapshot = LibrarySnapshot.fromJson({
        'continue_watching': [
          {
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': 'Breaking Bad',
            'status': 'watching',
            'current_season': 1,
            'current_episode': 4,
            'position_secs': 500,
            'duration_secs': 2500,
            'watched_episodes': ['1:1', '1:2'],
            'updated_at': '2026-11-23T12:00:00Z',
            'has_new_episodes': true,
            'new_episodes_count': 2,
          },
        ],
        'saved': [],
        'completed': [],
        'items': [
          {
            'id': 1396,
            'kind': 'tv',
            'is_anime': false,
            'title': 'Breaking Bad',
            'status': 'watching',
            'current_season': 1,
            'current_episode': 4,
            'position_secs': 500,
            'duration_secs': 2500,
            'watched_episodes': ['1:1', '1:2'],
            'updated_at': '2026-11-23T12:00:00Z',
            'has_new_episodes': true,
            'new_episodes_count': 2,
          },
        ],
      });

      expect(snapshot.continueWatching.length, 1);
      expect(snapshot.continueWatching.first.progressRatio, closeTo(0.2, 0.001));
      expect(snapshot.continueWatching.first.isEpisodeWatched(1, 2), isTrue);
      expect(snapshot.continueWatching.first.hasNewEpisodes, isTrue);

      final health = HealthStatus.fromJson({
        'status': 'ok',
        'service': 'easystreamapi',
        'version': '1.0.0',
      }, latencyMs: 14);
      expect(health.isOnline, isTrue);
      expect(health.version, '1.0.0');
    });
  });

  group('ApiClient HTTP contract', () {
    test('covers search, discover, genres, media, season, resolve, torrents, and library', () async {
      final requests = <String>[];
      final bodies = <String, Map<String, dynamic>>{};

      final mockClient = MockClient((req) async {
        requests.add('${req.method} ${req.url.path}${req.url.hasQuery ? "?${req.url.query}" : ""}');
        if (req.body.isNotEmpty) {
          bodies['${req.method} ${req.url.path}'] =
              json.decode(req.body) as Map<String, dynamic>;
        }

        final path = req.url.path;
        if (path == '/health') {
          return http.Response(
            json.encode({
              'status': 'ok',
              'service': 'easystreamapi',
              'version': '1.0.0',
            }),
            200,
          );
        }
        if (path == '/search' || path == '/discover') {
          return http.Response(
            json.encode([
              {
                'id': 550,
                'kind': 'movie',
                'is_anime': false,
                'title': 'Fight Club',
                'year': '1999',
              },
            ]),
            200,
          );
        }
        if (path == '/genres') {
          return http.Response(
            json.encode([
              {'slug': 'action', 'label': 'Azione'},
            ]),
            200,
          );
        }
        if (path == '/media/tv/1396') {
          return http.Response(
            json.encode({
              'id': 1396,
              'kind': 'tv',
              'is_anime': false,
              'title': 'Breaking Bad',
              'genres': ['Crime'],
              'seasons': [],
            }),
            200,
          );
        }
        if (path == '/media/tv/1396/season/1') {
          return http.Response(
            json.encode({
              'season_number': 1,
              'name': 'Stagione 1',
              'episodes': [
                {'episode_number': 1, 'name': 'Pilot', 'watched': false},
              ],
            }),
            200,
          );
        }
        if (path == '/stream/resolve/tv/1396') {
          return http.Response(
            json.encode({
              'id': 1396,
              'kind': 'tv',
              'is_anime': false,
              'title': 'Breaking Bad',
              'season': 1,
              'episode': 1,
              'recommended_mode': 'torrent',
              'recommended_url': '/stream/torrent/abc123?file_idx=0',
              'recommended_info_hash': 'abc123',
              'torrents': [],
            }),
            200,
          );
        }
        if (path == '/torrents/abc123' && req.method == 'DELETE') {
          return http.Response(
            json.encode({'status': 'stopped', 'info_hash': 'abc123'}),
            200,
          );
        }
        if (path == '/torrents' && req.method == 'DELETE') {
          return http.Response(json.encode({'status': 'stopped'}), 200);
        }
        if (path == '/library') {
          return http.Response(
            json.encode({
              'continue_watching': [],
              'saved': [],
              'completed': [],
              'items': [],
            }),
            200,
          );
        }
        if (path == '/library/updates') {
          return http.Response(json.encode([]), 200);
        }
        if (path == '/library/tv/1396' && req.method == 'PUT') {
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
              'updated_at': '2026-11-23T12:00:00Z',
              'has_new_episodes': false,
              'new_episodes_count': 0,
            }),
            200,
          );
        }
        if (path == '/library/tv/1396' && req.method == 'DELETE') {
          return http.Response(json.encode({'deleted': true}), 200);
        }
        if (path == '/library/tv/1396/progress' ||
            path == '/library/tv/1396/watched') {
          return http.Response(
            json.encode({
              'id': 1396,
              'kind': 'tv',
              'is_anime': false,
              'title': 'Breaking Bad',
              'status': 'watching',
              'current_season': 1,
              'current_episode': 1,
              'position_secs': 120,
              'duration_secs': 2400,
              'watched_episodes': ['S1E1'],
              'updated_at': '2026-11-23T12:00:00Z',
              'has_new_episodes': false,
              'new_episodes_count': 0,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiClient(
        baseUrlProvider: () => 'http://192.168.1.50:5555/',
        httpClient: mockClient,
      );

      expect(api.baseUrl, 'http://192.168.1.50:5555');
      expect(
        api.resolveStreamUrl('/stream/torrent/abc123?file_idx=0'),
        'http://192.168.1.50:5555/stream/torrent/abc123?file_idx=0',
      );
      expect(
        api.resolveStreamUrl('https://cdn.example.com/master.m3u8'),
        'https://cdn.example.com/master.m3u8',
      );

      expect((await api.checkHealth()).isOnline, isTrue);
      expect((await api.search('fight', type: 'movie', lang: 'en')).length, 1);
      expect((await api.discover(category: 'trending', lang: 'it')).length, 1);
      expect((await api.getGenres()).single.slug, 'action');
      expect((await api.getMediaDetail(MediaKind.tv, 1396)).title, 'Breaking Bad');
      expect((await api.getSeasonDetail(1396, 1)).episodes.single.name, 'Pilot');

      final resolved = await api.resolveStream(
        kind: MediaKind.tv,
        id: 1396,
        season: 1,
        episode: 1,
        lang: 'it',
        quality: '1080p',
        source: 'torrent',
      );
      expect(resolved.recommendedInfoHash, 'abc123');
      expect(await api.stopTorrent('abc123'), isTrue);
      expect(await api.stopAllTorrents(), isTrue);

      await api.getLibrary(lang: 'it');
      await api.getLibraryUpdates(lang: 'it');
      await api.upsertLibrary(
        kind: MediaKind.tv,
        id: 1396,
        isAnime: false,
        title: 'Breaking Bad',
        status: WatchStatus.saved,
      );
      expect(bodies['PUT /library/tv/1396']?['status'], 'saved');

      await api.reportProgress(
        kind: MediaKind.tv,
        id: 1396,
        isAnime: false,
        title: 'Breaking Bad',
        season: 1,
        episode: 1,
        positionSecs: 120,
        durationSecs: 2400,
      );
      expect(bodies['POST /library/tv/1396/progress']?['position_secs'], 120);

      await api.toggleWatched(
        kind: MediaKind.tv,
        id: 1396,
        season: 1,
        episode: 1,
        watched: true,
        isAnime: false,
        title: 'Breaking Bad',
      );
      expect(bodies['POST /library/tv/1396/watched']?['watched'], isTrue);
      expect(await api.deleteLibraryItem(MediaKind.tv, 1396), isTrue);

      expect(requests, contains('DELETE /torrents/abc123'));
      expect(requests, contains('DELETE /torrents'));
      expect(
        requests,
        contains(
          'GET /stream/resolve/tv/1396?season=1&episode=1&lang=it&quality=1080p&source=torrent',
        ),
      );
    });

    test('throws ApiException on non-2xx responses', () async {
      final api = ApiClient(
        baseUrlProvider: () => 'http://localhost:5555',
        httpClient: MockClient(
          (_) async => http.Response(
            json.encode({'error': 'TMDB_READ_API mancante'}),
            503,
          ),
        ),
      );

      expect(
        () => api.search('matrix'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.message, 'message', contains('TMDB_READ_API')),
        ),
      );
    });
  });
}
