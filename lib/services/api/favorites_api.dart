import 'package:onlystream/services/api/api_client.dart';

class FavoritesApi {
  /// Recupera l'elenco dei preferiti memorizzati nella watchlist persistente del server.
  /// Endpoint: GET /favorites
  /// Riceve:
  ///   - `type` (String?, opzionale): Filtro sul tipo di contenuto ('movie', 'tv', 'anime'). Se omesso restituisce tutti i preferiti.
  /// Ritorna:
  ///   - `Future<List<Map<String, dynamic>>>`: Lista di elementi FavoriteItem salvati su disco.
  static Future<List<Map<String, dynamic>>> getFavorites({
    String? type,
  }) async {
    final Map<String, dynamic> params = {};
    if (type != null && type.isNotEmpty) {
      params['type'] = type;
    }
    final data = await ApiClient.get('/favorites', queryParameters: params);
    final List<Map<String, dynamic>> favorites = [];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          favorites.add(item);
        }
      }
    }
    return favorites;
  }

  /// Aggiunge o aggiorna un titolo (film, serie TV o anime) nella lista dei preferiti persistente.
  /// Endpoint: POST /favorites
  /// Riceve:
  ///   - `favoriteData` (`Map<String, dynamic>`): Dati del preferito (campi: 'id', 'media_type', 'title', opzionali: 'poster_url', 'season', 'episode', ecc.).
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: L'oggetto FavoriteItem creato con timestamp, o null in caso di fallimento.
  static Future<Map<String, dynamic>?> addFavorite(
    Map<String, dynamic> favoriteData,
  ) async {
    final data = await ApiClient.post('/favorites', body: favoriteData);
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  /// Rimuove un titolo specifico dalla lista dei preferiti.
  /// Endpoint: DELETE /favorites/{media_type}/{id}
  /// Riceve:
  ///   - `mediaType` (String): Tipologia del contenuto da rimuovere ('movie', 'tv' o 'anime').
  ///   - `id` (dynamic): Identificativo numerico o stringa del titolo.
  /// Ritorna:
  ///   - `Future<bool>`: true se il contenuto è stato rimosso con successo, false in caso di errore.
  static Future<bool> deleteFavorite(String mediaType, dynamic id) async {
    final data = await ApiClient.delete('/favorites/$mediaType/$id');
    if (data is Map<String, dynamic> && data['removed'] == true) {
      return true;
    }
    return false;
  }

  /// Verifica se uno specifico contenuto è già presente nella lista dei preferiti.
  /// Endpoint: GET /favorites/check/{media_type}/{id}
  /// Riceve:
  ///   - `mediaType` (String): Tipologia del contenuto ('movie', 'tv' o 'anime').
  ///   - `id` (dynamic): Identificativo numerico o stringa del titolo.
  /// Ritorna:
  ///   - `Future<bool>`: true se il contenuto è presente nei preferiti, false altrimenti.
  static Future<bool> checkFavorite(String mediaType, dynamic id) async {
    final data = await ApiClient.get('/favorites/check/$mediaType/$id');
    if (data is Map<String, dynamic> && data['is_favorite'] == true) {
      return true;
    }
    return false;
  }
}
