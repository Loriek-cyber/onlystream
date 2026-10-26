import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlystream/main.dart';
import 'package:onlystream/models/video_model.dart';

void main() {
  testWidgets('OnlyStream HomeScreen renders search, tabs, and server badge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('OnlyStream'), findsOneWidget);
    expect(
      find.textContaining('Ricerca Unificata'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsWidgets);
  });

  test('Unified models parse EasyStream API JSON payloads', () {
    final torrent = TorrentItem.fromJson({
      'title': 'Breaking.Bad.S01E01.1080p.WEB-DL.ITA.mkv',
      'info_hash': '6a12ce77043c07604314f30fa62f2b17ea8d4ab9',
      'magnet':
          'magnet:?xt=urn:btih:6a12ce77043c07604314f30fa62f2b17ea8d4ab9',
      'quality': '1080p',
      'seeders': 979,
      'size_bytes': 2235550686,
      'languages': ['ita', 'eng'],
      'cached': true,
    });

    expect(torrent.quality, Quality.p1080);
    expect(torrent.seeders, 979);
    expect(torrent.cached, isTrue);
    expect(torrent.formattedSize, '2.08 GB');

    final searchItem = UnifiedSearchResult.fromTmdbJson({
      'id': 1396,
      'title': 'Breaking Bad',
      'media_type': 'tv',
      'release_date': '2008-01-20',
      'vote_average': 8.9,
    });
    expect(searchItem.id, 1396);
    expect(searchItem.mediaKind, MediaKind.tv);
    expect(searchItem.year, '2008');
  });
}
