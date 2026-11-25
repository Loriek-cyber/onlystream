import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onlystream/models/library.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/screens/media_detail_screen.dart';
import 'package:onlystream/screens/settings_screen.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/media_cards.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;
  final bool loadOnInit;

  const HomeScreen({
    super.key,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
    this.loadOnInit = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiClient _apiClient;
  late final ConfigService _config;
  late final LibraryService _library;

  bool _loadingDiscover = false;
  bool _startingCompanion = false;
  bool _discoverFailed = false;

  List<MediaSummary> _trending = const [];
  List<MediaSummary> _movies = const [];
  List<MediaSummary> _tv = const [];
  List<MediaSummary> _anime = const [];

  String _lastLang = '';
  String _lastBaseUrl = '';

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;

    _lastLang = _config.language;
    _lastBaseUrl = _config.baseUrl;

    _config.addListener(_onConfigChanged);
    _library.addListener(_onLibraryChanged);

    if (widget.loadOnInit) {
      unawaited(_reloadAll());
    }
  }

  void _onConfigChanged() {
    if (!mounted) return;
    final changed =
        _config.language != _lastLang || _config.baseUrl != _lastBaseUrl;
    if (changed) {
      _lastLang = _config.language;
      _lastBaseUrl = _config.baseUrl;
      unawaited(_reloadAll());
    } else {
      setState(() {});
    }
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _library.removeListener(_onLibraryChanged);
    super.dispose();
  }

  Future<void> _reloadAll() async {
    setState(() {
      _loadingDiscover = true;
      _discoverFailed = false;
    });

    final lang = _config.language;
    final libraryFuture = _library.refresh(lang: lang);
    final resultsFuture = Future.wait<List<MediaSummary>>([
      _apiClient.discover(category: 'trending', lang: lang),
      _apiClient.discover(category: 'movies', lang: lang),
      _apiClient.discover(category: 'tv', lang: lang),
      _apiClient.discover(category: 'anime', lang: lang),
    ]);

    try {
      final lists = await resultsFuture;
      await libraryFuture;
      if (!mounted) return;
      setState(() {
        _trending = lists[0];
        _movies = lists[1];
        _tv = lists[2];
        _anime = lists[3];
        _loadingDiscover = false;
        _discoverFailed = false;
      });
    } catch (_) {
      await libraryFuture;
      if (!mounted) return;
      setState(() {
        _loadingDiscover = false;
        _discoverFailed = true;
      });
    }
  }

  Future<void> _startLocalCompanion() async {
    setState(() => _startingCompanion = true);
    final ok = await _config.startLocalServer();
    if (!mounted) return;
    setState(() => _startingCompanion = false);
    if (ok && _config.status.isOnline) {
      await _reloadAll();
    }
  }

  void _openDetail(MediaSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailScreen(
          summary: summary,
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
        ),
      ),
    );
  }

  void _resumeFromLibrary(LibraryItemView item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          media: MediaSummary.fromLibrary(item),
          season: item.currentSeason ?? item.nextEpisode?.season ?? 1,
          episode: item.currentEpisode ?? item.nextEpisode?.episode ?? 1,
          initialLanguage: item.preferredLang ?? _config.language,
          initialPositionSecs: item.positionSecs,
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsScreen(configService: _config, apiClient: _apiClient),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final continueWatching = _library.continueWatching;
    final newEpisodes = _library.newEpisodesItems;
    final showOfflineBanner =
        (!_config.status.isOnline && !_config.isChecking) || _discoverFailed;

    return RefreshIndicator(
      color: AppColors.textPrimary,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        await _config.checkHealth();
        await _reloadAll();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          if (showOfflineBanner)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: _OfflineBanner(
                baseUrl: _config.baseUrl,
                showStartLocal: _config.isAndroid && _config.companionInstalled,
                startingLocal: _startingCompanion,
                onRetry: () async {
                  await _config.checkHealth();
                  await _reloadAll();
                },
                onOpenSettings: _openSettings,
                onStartLocal: _startLocalCompanion,
              ),
            ),
          if (continueWatching.isNotEmpty) ...[
            const _RowHeader(title: 'Continua a guardare'),
            SizedBox(
              height: 202,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: continueWatching.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final item = continueWatching[index];
                  return ContinueWatchingCard(
                    item: item,
                    onTap: () => _resumeFromLibrary(item),
                    onInfoTap: () => _openDetail(MediaSummary.fromLibrary(item)),
                  );
                },
              ),
            ),
          ],
          if (newEpisodes.isNotEmpty) ...[
            const _RowHeader(title: 'Nuovi episodi'),
            SizedBox(
              height: 112,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: newEpisodes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = newEpisodes[index];
                  return _NewEpisodeChipCard(
                    item: item,
                    onTap: () => _openDetail(MediaSummary.fromLibrary(item)),
                  );
                },
              ),
            ),
          ],
          if (_loadingDiscover &&
              _trending.isEmpty &&
              _movies.isEmpty &&
              _tv.isEmpty &&
              _anime.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_trending.isNotEmpty)
            _DiscoverPosterRow(
              title: 'In tendenza',
              items: _trending,
              onTap: _openDetail,
            ),
          if (_movies.isNotEmpty)
            _DiscoverPosterRow(
              title: 'Film',
              items: _movies,
              onTap: _openDetail,
            ),
          if (_tv.isNotEmpty)
            _DiscoverPosterRow(
              title: 'Serie TV',
              items: _tv,
              onTap: _openDetail,
            ),
          if (_anime.isNotEmpty)
            _DiscoverPosterRow(
              title: 'Anime',
              items: _anime,
              onTap: _openDetail,
            ),
        ],
      ),
    );
  }
}

class _RowHeader extends StatelessWidget {
  final String title;

  const _RowHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _DiscoverPosterRow extends StatelessWidget {
  final String title;
  final List<MediaSummary> items;
  final void Function(MediaSummary) onTap;

  const _DiscoverPosterRow({
    required this.title,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RowHeader(title: title),
        SizedBox(
          height: 260,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = items[index];
              return PosterMediaCard(
                item: item,
                width: 132,
                onTap: () => onTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NewEpisodeChipCard extends StatelessWidget {
  final LibraryItemView item;
  final VoidCallback onTap;

  const _NewEpisodeChipCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeText = item.newEpisodesCount > 0
        ? '+${item.newEpisodesCount} nuovi episodi'
        : 'Nuovi episodi';

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 240,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
          children: [
            SizedBox(
              width: 58,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: MediaNetworkImage(
                  url: item.poster,
                  borderRadius: BorderRadius.circular(8),
                  fallbackIcon: Icons.tv_outlined,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          badgeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final String baseUrl;
  final bool showStartLocal;
  final bool startingLocal;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onStartLocal;

  const _OfflineBanner({
    required this.baseUrl,
    required this.showStartLocal,
    required this.startingLocal,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onStartLocal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Server non raggiungibile',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Impossibile contattare $baseUrl. Puoi comunque consultare la tua libreria locale.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (showStartLocal)
                FilledButton(
                  onPressed: startingLocal ? null : onStartLocal,
                  child: Text(
                    startingLocal ? 'Avvio...' : 'Avvia server locale',
                  ),
                ),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Riprova'),
              ),
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('Impostazioni'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
