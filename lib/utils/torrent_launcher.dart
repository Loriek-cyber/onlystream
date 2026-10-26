import 'dart:io';

import 'package:flutter/services.dart';

/// Utilities for launching Magnet URIs in the user's OS default torrent client
/// (`xdg-open`, `open`, `start`), copying to clipboard, or launching external players (VLC, mpv, IINA).
class TorrentLauncher {
  /// Open a `magnet:?xt=urn:btih:...` URI in the default OS torrent client.
  static Future<bool> openMagnetInExternalClient(String magnetUri) async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [magnetUri]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
        final result = await Process.run('open', [magnetUri]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result =
            await Process.run('cmd', ['/c', 'start', '', magnetUri]);
        return result.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Open a stream URL or magnet in VLC, mpv, or WebTorrent/Peerflix if installed.
  static Future<bool> openInExternalPlayer(String urlOrMagnet) async {
    final candidates = ['mpv', 'vlc', 'iina', 'celluloid'];
    for (final bin in candidates) {
      try {
        final which = await Process.run(
          Platform.isWindows ? 'where' : 'which',
          [bin],
        );
        if (which.exitCode == 0) {
          await Process.start(
            bin,
            [urlOrMagnet],
            mode: ProcessStartMode.detached,
          );
          return true;
        }
      } catch (_) {}
    }
    return openMagnetInExternalClient(urlOrMagnet);
  }

  /// Open the local folder containing a downloaded file.
  static Future<bool> openFolder(String fileOrDirPath) async {
    try {
      final entity = File(fileOrDirPath);
      final targetDir =
          await entity.exists() ? entity.parent.path : fileOrDirPath;
      if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [targetDir]);
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('open', [targetDir]);
        return res.exitCode == 0;
      } else if (Platform.isWindows) {
        final res = await Process.run('explorer', [targetDir]);
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
