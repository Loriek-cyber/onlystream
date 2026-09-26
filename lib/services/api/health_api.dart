import 'package:onlystream/services/api/api_client.dart';

class HealthApi {
  /// Verifica lo stato del servizio e la raggiungibilità del server EasyStream API.
  /// Endpoint: GET /health (con fallback su /helth)
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<bool>`: true se il server risponde con status 'ok' (codice HTTP 200), false altrimenti.
  static Future<bool> checkHealth() async {
    final healthData = await ApiClient.get('/health');
    if (healthData is Map<String, dynamic> && healthData['status'] == 'ok') {
      return true;
    }
    final fallbackData = await ApiClient.get('/helth');
    if (fallbackData is Map<String, dynamic> && fallbackData['status'] == 'ok') {
      return true;
    }
    return false;
  }

  /// Recupera le informazioni dettagliate di versione e stato del backend EasyStream API.
  /// Endpoint: GET /health
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<Map<String, dynamic>?>`: Mappa contenente i campi 'service', 'status' e 'version', oppure null se offline.
  static Future<Map<String, dynamic>?> getHealthDetails() async {
    final data = await ApiClient.get('/health');
    if (data is Map<String, dynamic>) {
      return data;
    }
    final fallback = await ApiClient.get('/helth');
    if (fallback is Map<String, dynamic>) {
      return fallback;
    }
    return null;
  }
}
