import 'package:onlystream/services/api_client.dart';

/// Tracks the currently active torrent `info_hash` in the player and
/// guarantees an idempotent `DELETE /torrents/{info_hash}` whenever switching
/// away from a torrent (to another torrent, to HLS, next episode, pause timeout,
/// background detach, or player disposal).
class TorrentSessionGuard {
  TorrentSessionGuard({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient.instance;

  final ApiClient _apiClient;
  String? _activeInfoHash;

  String? get activeInfoHash => _activeInfoHash;
  bool get hasActiveTorrent =>
      _activeInfoHash != null && _activeInfoHash!.isNotEmpty;

  /// Registers [infoHash] as the active torrent stream. If a different torrent
  /// was active, it is stopped on the backend first.
  Future<void> activateTorrent(String infoHash) async {
    final normalized = infoHash.trim().toLowerCase();
    if (normalized.isEmpty) return;

    if (_activeInfoHash != null && _activeInfoHash != normalized) {
      await stopActive();
    }
    _activeInfoHash = normalized;
  }

  /// Stops any active torrent when switching playback to HLS.
  Future<void> switchToHls() => stopActive();

  /// Idempotently stops the currently active torrent on the EasyStream API.
  Future<void> stopActive() async {
    final hash = _activeInfoHash;
    _activeInfoHash = null;
    if (hash == null || hash.isEmpty) return;

    try {
      await _apiClient.stopTorrent(hash);
    } catch (_) {
      // Best-effort cleanup; never throw during lifecycle teardown.
    }
  }
}
