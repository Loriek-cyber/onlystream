import 'package:flutter_test/flutter_test.dart';
import 'package:onlystream/services/api/discovery_api.dart';
import 'package:onlystream/test/test_player.dart';

/// Esegue la suite di test automatizzati per il modulo DiscoveryApi e per la gestione di stagioni ed episodi.
/// Riceve: Nessun parametro.
/// Ritorna: void.
void main() {
  test('DiscoveryApi getTvSeasons correctly sorts regular seasons first and extracts all episodes', () async {
    final seasons = await DiscoveryApi.getTvSeasons('1396');

    expect(seasons, isNotEmpty);
    expect(seasons.first.number, equals(1));
    expect(seasons.first.name, equals('Stagione 1'));
    expect(seasons.first.list_episode.length, equals(7));
    expect(seasons.first.list_episode.first.number, equals(1));
    expect(seasons.first.list_episode.last.number, equals(7));

    final seasonNumbers = seasons.map((s) => s.number).toList();
    expect(seasonNumbers.contains(1), isTrue);
    expect(seasonNumbers.contains(2), isTrue);
    expect(seasonNumbers.contains(3), isTrue);
    expect(seasonNumbers.contains(4), isTrue);
    expect(seasonNumbers.contains(5), isTrue);

    if (seasonNumbers.contains(0)) {
      expect(seasons.last.number, equals(0));
    }
  });

  test('TvShowModel stores seasons and calculates length properly', () {
    final show = TestData.breakingBadSeries;
    expect(show.sesson, isNotEmpty);
    expect(show.lenSesson(), equals(1));
    expect(show.sesson.first.list_episode.length, equals(2));
    expect(show.getType(), equals('serie'));
  });

  test('DiscoveryApi getTvSeasons provides fallback for unknown ID', () async {
    final seasons = await DiscoveryApi.getTvSeasons('999999999');
    expect(seasons, isNotEmpty);
    expect(seasons.first.number, equals(1));
    expect(seasons.first.list_episode.length, equals(10));
  });
}
