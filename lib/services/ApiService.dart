import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/services/api/api.dart';

class Apiservice {
  /// Verifica lo stato del servizio e la raggiungibilità del server backend.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<bool>`: true se il server risponde con successo, false altrimenti.
  static Future<bool> checkHelth() {
    return HealthApi.checkHealth();
  }

  /// Cerca film e serie TV sul database TMDB tramite stringa di ricerca.
  /// Riceve:
  ///   - `q` (String): Testo o titolo cercato dall'utente.
  /// Ritorna:
  ///   - `Future<List<VideoModel>>`: Lista di contenuti trovati (MovieModel e TvShowModel).
  static Future<List<VideoModel>> search(String q) {
    return SearchApi.search(q);
  }

  /// Recupera i contenuti attualmente di tendenza dal database TMDB.
  /// Riceve:
  ///   - `window` (String, default 'day'): Intervallo temporale di tendenza ('day' o 'week').
  /// Ritorna:
  ///   - `Future<List<VideoModel>>`: Lista di contenuti di tendenza.
  static Future<List<VideoModel>> getTrending({String window = 'day'}) {
    return DiscoveryApi.getTrending(window: window);
  }
}
