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

class ProviderUrls {
  final String vixsrcUrl;
  final String animeunityUrl;
  final String animeworldUrl;
  final String corsaroUrl;
  final String torrentioUrl;

  const ProviderUrls({
    required this.vixsrcUrl,
    required this.animeunityUrl,
    required this.animeworldUrl,
    required this.corsaroUrl,
    required this.torrentioUrl,
  });

  factory ProviderUrls.fromJson(Map<String, dynamic> json) {
    return ProviderUrls(
      vixsrcUrl: json['vixsrc_url']?.toString() ?? '',
      animeunityUrl: json['animeunity_url']?.toString() ?? '',
      animeworldUrl: json['animeworld_url']?.toString() ?? '',
      corsaroUrl: json['corsaro_url']?.toString() ?? '',
      torrentioUrl: json['torrentio_url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'vixsrc_url': vixsrcUrl,
    'animeunity_url': animeunityUrl,
    'animeworld_url': animeworldUrl,
    'corsaro_url': corsaroUrl,
    'torrentio_url': torrentioUrl,
  };
}

class ProviderSourcesConfig {
  final ProviderUrls sources;
  final ProviderUrls defaults;

  const ProviderSourcesConfig({
    required this.sources,
    required this.defaults,
  });

  factory ProviderSourcesConfig.fromJson(Map<String, dynamic> json) {
    final sourcesMap = json['sources'] is Map<String, dynamic>
        ? json['sources'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final defaultsMap = json['defaults'] is Map<String, dynamic>
        ? json['defaults'] as Map<String, dynamic>
        : sourcesMap;
    return ProviderSourcesConfig(
      sources: ProviderUrls.fromJson(sourcesMap),
      defaults: ProviderUrls.fromJson(defaultsMap),
    );
  }
}
