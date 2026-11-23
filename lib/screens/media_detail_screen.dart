import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onlystream/models/library.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/media_cards.dart';
import 'package:url_launcher/url_launcher.dart';

class MediaDetailScreen extends StatefulWidget {
  final MediaSummary summary;
  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;
  final Future<bool> Function(Uri uri)? urlLauncher;

  const MediaDetailScreen({
    super.key,
    required this.summary,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
    this.urlLauncher,
  });

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  late final ApiClient _apiClient;
  late final ConfigService _config;
  late final LibraryService _library;

  MediaDetail? _detail;
  SeasonDetail? _seasonDetail;
  bool _loadingDetail = true;
  bool _loadingSeason = false;
  String? _detailError;

  late String _lang;
  late String _source;
  late String _quality;

  int _selectedSeason = 1;
  int _selectedEpisode = 1;

  bool _loadingTorrents = false;
  List<TorrentSource> _torrents = const [];
  String? _torrentError;
  int _torrentEpoch = 0;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;

    final tracked = _library.entryFor(widget.summary.kind, widget.summary.id);
    _lang = tracked?.preferredLang ?? _config.language;
    _source = _config.source;
    _quality = _config.quality;
    _selectedSeason = tracked?.currentSeason ?? 1;
    _selectedEpisode = tracked?.currentEpisode ?? 1;

    _library.addListener(_onLibraryChanged);
    unawaited(_loadDetail());
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loadingDetail = true;
      _detailError = null;
    });

    try {
      final detail = await _apiClient.getMediaDetail(
        widget.summary.kind,
        widget.summary.id,
        lang: _lang,
      );
      if (!mounted) return;

      _library.mergeServerItem(detail.library);

      int seasonToLoad = _selectedSeason;
      if (detail.kind == MediaKind.tv && detail.seasons.isNotEmpty) {
        final hasSelected = detail.seasons.any(
          (s) => s.seasonNumber == seasonToLoad,
        );
        if (!hasSelected) {
          final firstRegular = detail.seasons.where((s) => s.seasonNumber > 0);
          seasonToLoad = firstRegular.isNotEmpty
              ? firstRegular.first.seasonNumber
              : detail.seasons.first.seasonNumber;
        }
      }

      setState(() {
        _detail = detail;
        _selectedSeason = seasonToLoad;
        _loadingDetail = false;
      });

      if (detail.kind == MediaKind.tv) {
        await _loadSeason(seasonToLoad);
      }

      if (_source == 'torrent') {
        await _loadTorrents();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _detailError = 'Impossibile caricare i dettagli: $e';
      });
    }
  }

  Future<void> _loadSeason(int seasonNumber) async {
    setState(() {
      _selectedSeason = seasonNumber;
      _loadingSeason = true;
    });
    try {
      final season = await _apiClient.getSeasonDetail(
        widget.summary.id,
        seasonNumber,
        lang: _lang,
      );
      if (!mounted) return;
      setState(() {
        _seasonDetail = season;
        _loadingSeason = false;
        if (season.episodes.isNotEmpty &&
            !season.episodes.any((e) => e.episodeNumber == _selectedEpisode)) {
          _selectedEpisode = season.episodes.first.episodeNumber;
        }
      });
      if (_source == 'torrent') {
        unawaited(_loadTorrents());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSeason = false);
    }
  }

  Future<void> _loadTorrents() async {
    final epoch = ++_torrentEpoch;
    setState(() {
      _loadingTorrents = true;
      _torrentError = null;
    });
    try {
      final resolved = await _apiClient.resolveStream(
        kind: widget.summary.kind,
        id: widget.summary.id,
        season: _selectedSeason,
        episode: _selectedEpisode,
        lang: _lang,
        quality: _quality,
        source: 'torrent',
      );
      if (!mounted || epoch != _torrentEpoch) return;
      setState(() {
        _torrents = resolved.torrents;
        _loadingTorrents = false;
      });
    } catch (e) {
      if (!mounted || epoch != _torrentEpoch) return;
      setState(() {
        _loadingTorrents = false;
        _torrentError = 'Impossibile cercare torrent: $e';
      });
    }
  }

  void _changeLanguage(String lang) {
    if (_lang == lang) return;
    setState(() => _lang = lang);
    unawaited(_loadDetail());
  }

  void _changeSource(String source) {
    if (_source == source) return;
    setState(() => _source = source);
    if (source == 'torrent') {
      unawaited(_loadTorrents());
    }
  }

  void _openPlayer({
    int? season,
    int? episode,
    String? episodeTitle,
    TorrentSource? torrent,
    int resumePositionSecs = 0,
  }) {
    final summary = _detail?.toSummary() ?? widget.summary;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          media: summary,
          season: season ?? _selectedSeason,
          episode: episode ?? _selectedEpisode,
          episodeTitle: episodeTitle,
          initialLanguage: _lang,
          initialQuality: _quality,
          initialSource: torrent != null ? 'torrent' : _source,
          initialTorrent: torrent,
          initialPositionSecs: resumePositionSecs,
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
        ),
      ),
    );
  }

  Future<void> _openMagnet(TorrentSource torrent) async {
    final uri = Uri.tryParse(torrent.magnet);
    var launched = false;
    if (uri != null && torrent.magnet.isNotEmpty) {
      try {
        if (widget.urlLauncher != null) {
          launched = await widget.urlLauncher!(uri);
        } else {
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        launched = false;
      }
    }

    if (!launched && torrent.magnet.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: torrent.magnet));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Magnet link copiato negli appunti')),
        );
      }
    }
  }

  Future<void> _toggleSaved() async {
    final detail = _detail;
    await _library.toggleSaved(
      kind: widget.summary.kind,
      id: widget.summary.id,
      isAnime: detail?.isAnime ?? widget.summary.isAnime,
      title: detail?.title ?? widget.summary.title,
      poster: detail?.poster ?? widget.summary.poster,
      backdrop: detail?.backdrop ?? widget.summary.backdrop,
      year: detail?.year ?? widget.summary.year,
    );
  }

  Future<void> _toggleEpisodeWatched(
    EpisodeDetail ep,
    bool currentlyWatched,
  ) async {
    final detail = _detail;
    setState(() {
      if (_seasonDetail != null) {
        _seasonDetail = SeasonDetail(
          seasonNumber: _seasonDetail!.seasonNumber,
          name: _seasonDetail!.name,
          episodes: _seasonDetail!.episodes
              .map(
                (item) => item.episodeNumber == ep.episodeNumber
                    ? item.copyWith(watched: !currentlyWatched)
                    : item,
              )
              .toList(),
        );
      }
    });

    await _library.toggleEpisodeWatched(
      kind: widget.summary.kind,
      id: widget.summary.id,
      season: _selectedSeason,
      episode: ep.episodeNumber,
      watched: !currentlyWatched,
      isAnime: detail?.isAnime ?? widget.summary.isAnime,
      title: detail?.title ?? widget.summary.title,
      poster: detail?.poster ?? widget.summary.poster,
      backdrop: detail?.backdrop ?? widget.summary.backdrop,
      year: detail?.year ?? widget.summary.year,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = detail?.title ?? widget.summary.title;
    final backdrop = detail?.backdrop ??
        widget.summary.backdrop ??
        detail?.poster ??
        widget.summary.poster;
    final year = detail?.year ?? widget.summary.year;
    final rating = detail?.rating ?? widget.summary.rating;
    final runtime = detail?.runtime;
    final genres = detail?.genres ?? const <String>[];
    final overview = detail?.overview ?? widget.summary.overview ?? '';
    final libraryEntry = _library.entryFor(
      widget.summary.kind,
      widget.summary.id,
    );
    final isTracked = libraryEntry != null;
    final isSeries = widget.summary.kind == MediaKind.tv;

    final hasResume = libraryEntry != null &&
        (libraryEntry.positionSecs > 0 ||
            (isSeries && libraryEntry.currentEpisode != null));
    final playLabel = hasResume
        ? (isSeries && libraryEntry.episodeLabel != null
            ? 'Riprendi ${libraryEntry.episodeLabel}'
            : 'Riprendi')
        : 'Riproduci';

    final metaParts = <String>[
      widget.summary.kindLabel,
      if (year != null && year.isNotEmpty) year,
      if (rating != null && rating > 0) rating.toStringAsFixed(1),
      if (runtime != null && runtime > 0) '$runtime min',
      ...genres.take(3),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  MediaNetworkImage(
                    url: backdrop,
                    fallbackIcon: isSeries
                        ? Icons.tv_outlined
                        : Icons.movie_outlined,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x550B0B0D),
                          Color(0x220B0B0D),
                          AppColors.background,
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      if (detail?.originalTitle != null &&
                          detail!.originalTitle!.isNotEmpty &&
                          detail.originalTitle != title) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail.originalTitle!,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (metaParts.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          metaParts.join(' · '),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              final resumeSecs = libraryEntry?.positionSecs ?? 0;
                              final targetSeason =
                                  libraryEntry?.currentSeason ?? _selectedSeason;
                              final targetEp = libraryEntry?.currentEpisode ??
                                  _selectedEpisode;
                              _openPlayer(
                                season: targetSeason,
                                episode: targetEp,
                                resumePositionSecs: resumeSecs,
                              );
                            },
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: Text(playLabel),
                          ),
                          OutlinedButton.icon(
                            onPressed: _toggleSaved,
                            icon: Icon(
                              isTracked
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              size: 18,
                            ),
                            label: Text(
                              isTracked
                                  ? (isSeries ? 'Seguito' : 'Salvato')
                                  : (isSeries ? 'Segui' : 'Salva'),
                            ),
                          ),
                        ],
                      ),
                      if (overview.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          overview,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _buildSelectors(),
                      if (_loadingDetail) ...[
                        const SizedBox(height: 24),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      if (_detailError != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _detailError!,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _loadDetail,
                                child: const Text('Riprova'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_source == 'torrent') ...[
                        const SizedBox(height: 24),
                        _buildTorrentSection(isSeries),
                      ],
                      if (isSeries && detail != null) ...[
                        const SizedBox(height: 28),
                        _buildSeasonsAndEpisodes(detail, libraryEntry),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectors() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Lingua',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: const [
                  ('it', 'IT'),
                  ('en', 'EN'),
                ].map((opt) {
                  return ChoiceChip(
                    label: Text(opt.$2),
                    selected: _lang == opt.$1,
                    onSelected: (_) => _changeLanguage(opt.$1),
                  );
                }).toList(),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sorgente',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: const [
                  ('auto', 'Auto'),
                  ('hls', 'HLS'),
                  ('torrent', 'Torrent'),
                ].map((opt) {
                  return ChoiceChip(
                    label: Text(opt.$2),
                    selected: _source == opt.$1,
                    onSelected: (_) => _changeSource(opt.$1),
                  );
                }).toList(),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Qualità',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: const [
                  ('auto', 'Auto'),
                  ('1080p', '1080p'),
                  ('720p', '720p'),
                ].map((opt) {
                  return ChoiceChip(
                    label: Text(opt.$2),
                    selected: _quality == opt.$1,
                    onSelected: (_) {
                      setState(() => _quality = opt.$1);
                      if (_source == 'torrent') {
                        unawaited(_loadTorrents());
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentSection(bool isSeries) {
    final targetLabel =
        isSeries ? 'Torrent · S$_selectedSeason · E$_selectedEpisode' : 'Torrent disponibili';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              targetLabel,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton.icon(
              onPressed: _loadingTorrents ? null : _loadTorrents,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Aggiorna'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingTorrents)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_torrentError != null)
          Text(
            _torrentError!,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          )
        else if (_torrents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nessun torrent trovato per questa selezione.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          )
        else
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _torrents.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final t = _torrents[index];
                final meta = <String>[
                  t.quality.toUpperCase(),
                  '${t.seeders} seed',
                  if (t.formattedSize.isNotEmpty) t.formattedSize,
                  if (t.languages.isNotEmpty)
                    t.languages.map((l) => l.toUpperCase()).join('/'),
                  if (t.cached) 'Cache',
                  if (t.sourceIndexer != null && t.sourceIndexer!.isNotEmpty)
                    t.sourceIndexer!,
                ];

                return ListTile(
                  title: Text(
                    t.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    meta.join(' · '),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Apri magnet link',
                    icon: const Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => _openMagnet(t),
                  ),
                  onTap: () => _openPlayer(
                    season: _selectedSeason,
                    episode: _selectedEpisode,
                    torrent: t,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSeasonsAndEpisodes(
    MediaDetail detail,
    LibraryItemView? libraryEntry,
  ) {
    final seasons = detail.seasons;
    if (seasons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Episodi',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: seasons.map((s) {
              final selected = s.seasonNumber == _selectedSeason;
              final label = s.seasonNumber == 0
                  ? 'Speciali'
                  : 'Stagione ${s.seasonNumber}';
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => _loadSeason(s.seasonNumber),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        if (_loadingSeason)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_seasonDetail == null || _seasonDetail!.episodes.isEmpty)
          const Text(
            'Nessun episodio disponibile per questa stagione.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _seasonDetail!.episodes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ep = _seasonDetail!.episodes[index];
              final isWatched = ep.watched ||
                  (libraryEntry?.isEpisodeWatched(
                        _selectedSeason,
                        ep.episodeNumber,
                      ) ??
                      false);

              return Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedEpisode = ep.episodeNumber);
                    _openPlayer(
                      season: _selectedSeason,
                      episode: ep.episodeNumber,
                      episodeTitle: ep.name,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 128,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: MediaNetworkImage(
                              url: ep.still ?? detail.backdrop,
                              fallbackIcon: Icons.play_circle_outline_rounded,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'E${ep.episodeNumber} · ${ep.name}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (ep.runtime != null && ep.runtime! > 0) ...[
                              const SizedBox(height: 3),
                              Text(
                                '${ep.runtime} min',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            if (ep.overview != null &&
                                ep.overview!.trim().isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                ep.overview!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: isWatched
                            ? 'Segna come non visto'
                            : 'Segna come visto',
                        icon: Icon(
                          isWatched
                              ? Icons.check_circle_rounded
                              : Icons.check_circle_outline_rounded,
                          color: isWatched
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                        onPressed: () => _toggleEpisodeWatched(ep, isWatched),
                      ),
                    ],
                  ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
