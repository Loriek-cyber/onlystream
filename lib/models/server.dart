class HealthStatus {
  final bool isOnline;
  final String service;
  final String version;
  final int latencyMs;
  final String? error;

  const HealthStatus({
    required this.isOnline,
    this.service = 'easystreamapi',
    this.version = '',
    this.latencyMs = 0,
    this.error,
  });

  factory HealthStatus.fromJson(
    Map<String, dynamic> json, {
    int latencyMs = 0,
  }) {
    return HealthStatus(
      isOnline: json['status'] == 'ok',
      service: json['service']?.toString() ?? 'easystreamapi',
      version: json['version']?.toString() ?? '',
      latencyMs: latencyMs,
    );
  }
}

class ServerPreset {
  final String name;
  final String url;

  const ServerPreset({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory ServerPreset.fromJson(Map<String, dynamic> json) {
    return ServerPreset(
      name: json['name']?.toString() ?? 'Server',
      url: json['url']?.toString() ?? 'http://localhost:5555',
    );
  }
}
