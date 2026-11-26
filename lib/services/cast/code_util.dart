import 'dart:io';

/// Web Video Caster-compatible Base36 IP/port pairing code utilities and LAN IPv4
/// detection.
abstract final class CodeUtil {
  static const int defaultPort = 30001;

  /// Encodes an RFC1918 private IPv4 address (`192.168.0.0/16`, `10.0.0.0/8`,
  /// `172.16.0.0/12`) into an uppercase Base36 pairing code.
  ///
  /// Returns `null` if [ip] is not a valid private IPv4 address.
  static String? ipToCode(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return null;

    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      octets.add(value);
    }

    final a = octets[0];
    final b = octets[1];
    final c = octets[2];
    final d = octets[3];

    if (a == 192 && b == 168) {
      final host = (c << 8) | d;
      return host.toRadixString(36).toUpperCase();
    }
    if (a == 172 && b >= 16 && b <= 31) {
      final host = ((b - 16) << 16) | (c << 8) | d;
      return host.toRadixString(36).toUpperCase();
    }
    if (a == 10) {
      final host = (b << 16) | (c << 8) | d;
      return host.toRadixString(36).toUpperCase();
    }

    return null;
  }

  /// Encodes a TCP port into an uppercase Base36 string.
  static String portToCode(int port) {
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    return port.toRadixString(36).toUpperCase();
  }

  /// Decodes a Base36 (or decimal fallback if invalid) port code.
  static int? decodePortCode(String? portCode) {
    if (portCode == null) return defaultPort;
    final clean = portCode.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (clean.isEmpty) return defaultPort;
    final parsed = int.tryParse(clean, radix: 36);
    if (parsed == null || parsed < 1 || parsed > 65535) return null;
    return parsed;
  }

  /// Expands a Base36 pairing [code] (and optional Base36 [portCode]) into all
  /// candidate LAN base URLs (`http://<ip>:<port>`) across `192.168.0.0/16`,
  /// `172.16.0.0/12`, and `10.0.0.0/8`.
  ///
  /// Returns an empty list if [code] or [portCode] is invalid.
  static List<String> codeToCandidateUrls(String code, {String? portCode}) {
    final cleanCode = code.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (cleanCode.isEmpty) return const [];

    final host = int.tryParse(cleanCode, radix: 36);
    if (host == null || host < 0 || host > 0xFFFFFF) return const [];

    final port = decodePortCode(portCode);
    if (port == null) return const [];

    final candidates = <String>[];

    // 192.168.0.0/16 (0 .. 0xFFFF)
    if (host <= 0xFFFF) {
      final c = (host >> 8) & 0xFF;
      final d = host & 0xFF;
      candidates.add('http://192.168.$c.$d:$port');
    }

    // 172.16.0.0/12 (0 .. 0xFFFFF)
    if (host <= 0xFFFFF) {
      final b = 16 + ((host >> 16) & 0x0F);
      final c = (host >> 8) & 0xFF;
      final d = host & 0xFF;
      candidates.add('http://172.$b.$c.$d:$port');
    }

    // 10.0.0.0/8 (0 .. 0xFFFFFF)
    final b = (host >> 16) & 0xFF;
    final c = (host >> 8) & 0xFF;
    final d = host & 0xFF;
    candidates.add('http://10.$b.$c.$d:$port');

    return candidates;
  }

  /// Detects the best local LAN IPv4 address using [NetworkInterface.list].
  ///
  /// Prioritizes physical Wi-Fi/Ethernet interfaces and RFC1918 ranges
  /// (`192.168.x.x` > `10.x.x.x` > `172.16-31.x.x`), skipping loopback,
  /// link-local (`169.254.x.x`), and virtual tunnel/container interfaces when
  /// a LAN interface is available.
  static Future<String?> detectLanIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final scored = <({String ip, int score})>[];
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isVirtual = name.startsWith('docker') ||
            name.startsWith('veth') ||
            name.startsWith('virbr') ||
            name.startsWith('br-') ||
            name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('tailscale') ||
            name.startsWith('wg');
        final isPreferredIface = name.startsWith('wlan') ||
            name.startsWith('wlp') ||
            name.startsWith('en') ||
            name.startsWith('eth');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (addr.isLoopback || ip.startsWith('169.254.')) continue;

          var score = 0;
          if (ip.startsWith('192.168.')) {
            score += 300;
          } else if (ip.startsWith('10.')) {
            score += 200;
          } else if (_is172Private(ip)) {
            score += 100;
          } else {
            score += 10;
          }

          if (isPreferredIface) score += 50;
          if (isVirtual) score -= 250;

          scored.add((ip: ip, score: score));
        }
      }

      if (scored.isEmpty) return null;
      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.first.ip;
    } catch (_) {
      return null;
    }
  }

  static bool _is172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '172') return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }
}
