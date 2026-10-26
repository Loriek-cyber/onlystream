import 'package:flutter/material.dart';
import 'package:onlystream/models/video_model.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/services/download_service.dart';
import 'package:onlystream/services/server_config_service.dart';
import 'package:onlystream/services/video_service.dart';
import 'package:onlystream/utils/torrent_launcher.dart';

/// Comprehensive Media Detail & Action Sheet supporting:
/// - Movie / TV Series (Seasons & Episodes) / Anime (AnimeUnity Episodes)
/// - "Salva nella Lista" & "Scarica" (Single Episode, Season Batch, or Full Series Batch)
/// - "Guarda Ora" (Direct HLS Stream with Quality/Language/Source selectors)
/// - "Torrent P2P" (Seeders, Quality, Cached status, Magnet copy, External Torrent Client, or Direct Stream)
class MediaDetailSheet extends StatefulWidget {
  final UnifiedSearchResult item;

  const MediaDetailSheet({super.key, required this.item});

  static Future<void> show(BuildContext context, UnifiedSearchResult item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaDetailSheet(item: item),
    );
  }

  @override
  State<MediaDetailSheet> createState() => _MediaDetailSheetState();
}

class _MediaDetailSheetState extends State<MediaDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _selectedLang = ServerConfigService.instance.defaultLanguage;
  String _selectedQuality = ServerConfigService.instance.preferredQuality;
  String _selectedSource = ServerConfigService.instance.preferredSource;

  int _selectedSeason = 1;
  int _selectedEpisode = 1;

  bool _isLoadingData = true;
  bool _isLoadingTorrents = false;
  DownloadMediaInfo? _downloadInfo;
  AnimeEpisodesResponse? _animeEpisodes;
  List<TorrentItem> _torrents = [];
  String _torrentQualityFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.item.mediaKind == MediaKind.movie ? 2 : 3,
      vsync: this,
    );
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);

    if (widget.item.mediaKind == MediaKind.anime) {
      final eps = await VideoService.fetchAnimeEpisodes(widget.item.id);
      if (mounted) {
        setState(() {
          _animeEpisodes = eps;
          _isLoadingData = false;
        });
      }
      return;
    }

    final dlInfo = await VideoService.fetchDownloadData(
      kind: widget.item.mediaKind,
      id: widget.item.id,
      season: _selectedSeason,
      episode: _selectedEpisode,
      language: _selectedLang,
      includeTorrents: true,
    );

    if (!mounted) return;

    setState(() {
      _downloadInfo = dlInfo;
      if (dlInfo != null && dlInfo.torrents.isNotEmpty) {
        _torrents = dlInfo.torrents;
      }
      if (dlInfo != null && dlInfo.seasons.isNotEmpty) {
        if (!dlInfo.seasons.any((s) => s.seasonNumber == _selectedSeason)) {
          _selectedSeason = dlInfo.seasons.first.seasonNumber;
        }
      }
      _isLoadingData = false;
    });

    if (_torrents.isEmpty && widget.item.mediaKind != MediaKind.anime) {
      _refreshTorrents();
    }
  }

  Future<void> _refreshTorrents() async {
    if (widget.item.mediaKind == MediaKind.anime) return;
    setState(() => _isLoadingTorrents = true);
    final list = await VideoService.fetchTorrents(
      kind: widget.item.mediaKind,
      rawId: widget.item.id.toString(),
      season: _selectedSeason,
      episode: _selectedEpisode,
      language: _selectedLang,
    );
    if (mounted) {
      setState(() {
        _torrents = list;
        _isLoadingTorrents = false;
      });
    }
  }

  void _openPlayer({int? season, int? episode, String? directStreamUrl}) {
    final s = season ?? _selectedSeason;
    final e = episode ?? _selectedEpisode;

    final video = Video(
      id: widget.item.id,
      title: widget.item.title,
      type: switch (widget.item.mediaKind) {
        MediaKind.movie => 'movie',
        MediaKind.tv => 'series',
        MediaKind.anime => 'anime',
      },
      audioTracks: [
        AudioTrack(language: 'Italiano', code: 'it'),
        AudioTrack(language: 'English', code: 'en'),
        AudioTrack(language: 'Japanese', code: 'ja'),
      ],
      currentEpisode: widget.item.mediaKind == MediaKind.movie
          ? null
          : Episode(
              season: s,
              number: e,
              title: widget.item.mediaKind == MediaKind.anime
                  ? 'Episodio $e'
                  : 'Stagione $s • Episodio $e',
            ),
      hasNext: widget.item.mediaKind != MediaKind.movie,
      posterUrl: widget.item.posterUrl ?? _downloadInfo?.posterUrl,
      backdropUrl: widget.item.backdropUrl ?? _downloadInfo?.backdropUrl,
      overview: widget.item.overview ?? _downloadInfo?.overview,
      directStreamUrl: directStreamUrl,
    );

    DownloadService.instance.addToHistory(video);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          video: video,
          initialLanguage: _selectedLang,
          initialQuality: _selectedQuality,
          initialSource: _selectedSource,
        ),
      ),
    );
  }

  Future<void> _handleSaveOrDownloadAction() async {
    if (widget.item.mediaKind == MediaKind.movie) {
      await DownloadService.instance.enqueueSingle(
        mediaId: widget.item.id,
        title: widget.item.title,
        mediaKind: MediaKind.movie,
        language: _selectedLang,
        quality: _selectedQuality,
        posterUrl: widget.item.posterUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF06B6D4),
            content: Text(
              'Download avviato: ${widget.item.title} ($_selectedQuality • ${_selectedLang.toUpperCase()})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      return;
    }

    // For TV Series / Anime: present options to download Current Episode, Current Season, or Full Series!
    _showSeriesDownloadModal();
  }

  void _showSeriesDownloadModal() {
    final seasons = _downloadInfo?.seasons ?? [];
    final currentSeasonSummary = seasons
        .where((s) => s.seasonNumber == _selectedSeason)
        .firstOrNull;
    final seasonEpCount = widget.item.mediaKind == MediaKind.anime
        ? (_animeEpisodes?.episodesCount ?? widget.item.episodesCount ?? 12)
        : (currentSeasonSummary?.episodeCount ?? 10);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121722),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.download_for_offline_rounded,
                        color: Color(0xFF06B6D4),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Salva / Scarica Serie: ${widget.item.title}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Qualità: ${_selectedQuality.toUpperCase()} • Audio: ${_selectedLang.toUpperCase()}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildDownloadOptionTile(
                  icon: Icons.play_lesson_rounded,
                  color: const Color(0xFF38BDF8),
                  title: widget.item.mediaKind == MediaKind.anime
                      ? 'Scarica Episodio $_selectedEpisode'
                      : 'Scarica Episodio Corrente (S${_selectedSeason.toString().padLeft(2, '0')}E${_selectedEpisode.toString().padLeft(2, '0')})',
                  subtitle: 'Salva in MP4 solo l\'episodio selezionato',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await DownloadService.instance.enqueueSingle(
                      mediaId: widget.item.id,
                      title: widget.item.title,
                      mediaKind: widget.item.mediaKind,
                      season: _selectedSeason,
                      episode: _selectedEpisode,
                      language: _selectedLang,
                      quality: _selectedQuality,
                      posterUrl: widget.item.posterUrl,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Episodio S${_selectedSeason}E$_selectedEpisode aggiunto alla coda di download!',
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                if (widget.item.mediaKind == MediaKind.tv)
                  _buildDownloadOptionTile(
                    icon: Icons.dynamic_feed_rounded,
                    color: const Color(0xFF8B5CF6),
                    title:
                        'Scarica Intera Stagione $_selectedSeason ($seasonEpCount episodi)',
                    subtitle:
                        'Mette in coda automaticamente tutti gli episodi della Stagione $_selectedSeason',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final count =
                          await DownloadService.instance.enqueueSeasonBatch(
                        mediaId: widget.item.id,
                        title: widget.item.title,
                        mediaKind: MediaKind.tv,
                        seasonNumber: _selectedSeason,
                        episodeCount: seasonEpCount,
                        language: _selectedLang,
                        quality: _selectedQuality,
                        posterUrl: widget.item.posterUrl,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Stagione $_selectedSeason ($count episodi) aggiunta alla coda di download!',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                if (widget.item.mediaKind == MediaKind.tv)
                  const SizedBox(height: 10),
                _buildDownloadOptionTile(
                  icon: Icons.library_add_check_rounded,
                  color: const Color(0xFF10B981),
                  title: widget.item.mediaKind == MediaKind.anime
                      ? 'Scarica Tutti gli Episodi Anime ($seasonEpCount ep.)'
                      : 'Scarica Serie Completa (${seasons.isEmpty ? "Tutte le stagioni" : "${seasons.length} stagioni"})',
                  subtitle:
                      'Salva e scarica l\'intera serie sul dispositivo in formato MP4',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final count =
                        await DownloadService.instance.enqueueFullSeries(
                      mediaId: widget.item.id,
                      title: widget.item.title,
                      mediaKind: widget.item.mediaKind,
                      knownSeasons: seasons,
                      knownAnimeEpisodes: seasonEpCount,
                      language: _selectedLang,
                      quality: _selectedQuality,
                      posterUrl: widget.item.posterUrl,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF10B981),
                          content: Text(
                            'Serie completa ($count episodi) messa in coda di download!',
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildDownloadOptionTile(
                  icon: Icons.terminal_rounded,
                  color: const Color(0xFFF59E0B),
                  title: 'Genera Comando FFmpeg Locale (Offload Veloce)',
                  subtitle:
                      'Ottieni il comando FFmpeg pronto da eseguire sul tuo terminale',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showFfmpegCommandDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadOptionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2232),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF28334B)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Future<void> _showFfmpegCommandDialog() async {
    final cmdInfo = await VideoService.fetchDownloadCommand(
      kind: widget.item.mediaKind,
      id: widget.item.id,
      season: _selectedSeason,
      episode: _selectedEpisode,
      language: _selectedLang,
      quality: _selectedQuality,
    );
    if (!mounted) return;
    if (cmdInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Impossibile generare il comando FFmpeg dal server.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121722),
        title: Text(
          'Comando FFmpeg: ${cmdInfo.filename}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cmdInfo.description,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF090C12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF232B3E)),
                ),
                child: SelectableText(
                  cmdInfo.command,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF06B6D4),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await TorrentLauncher.copyToClipboard(cmdInfo.command);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Comando FFmpeg copiato negli appunti!'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copia Comando'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = DownloadService.instance.isSaved(
      widget.item.id,
      widget.item.mediaKind,
    );
    final overview =
        widget.item.overview ?? _downloadInfo?.overview ?? 'Nessuna trama disponibile.';
    final backdrop = widget.item.backdropUrl ??
        _downloadInfo?.backdropUrl ??
        widget.item.posterUrl;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0E131D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),

              // Hero Header
              _buildHeroHeader(backdrop, overview, isSaved),

              // Stream & Download Options Bar (Language, Quality, Source)
              _buildOptionsToolbar(),

              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF06B6D4),
                labelColor: const Color(0xFF38BDF8),
                unselectedLabelColor: const Color(0xFF94A3B8),
                tabs: [
                  if (widget.item.mediaKind != MediaKind.movie)
                    Tab(
                      icon: const Icon(Icons.video_library_rounded, size: 18),
                      text: widget.item.mediaKind == MediaKind.anime
                          ? 'Episodi Anime'
                          : 'Stagioni & Episodi',
                    ),
                  Tab(
                    icon: const Icon(Icons.hub_rounded, size: 18),
                    text: 'Torrent P2P (${_torrents.length})',
                  ),
                  const Tab(
                    icon: Icon(Icons.tune_rounded, size: 18),
                    text: 'Flussi HLS & Info',
                  ),
                ],
              ),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    if (widget.item.mediaKind != MediaKind.movie)
                      _buildEpisodesTab(scrollController),
                    _buildTorrentsTab(scrollController),
                    _buildHlsPackagesTab(scrollController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroHeader(String? backdrop, String overview, bool isSaved) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: widget.item.posterUrl != null
                    ? Image.network(
                        widget.item.posterUrl!,
                        width: 88,
                        height: 128,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildPosterFallback(),
                      )
                    : _buildPosterFallback(),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: widget.item.mediaKind == MediaKind.anime
                                  ? [
                                      const Color(0xFFF43F5E),
                                      const Color(0xFFFB923C),
                                    ]
                                  : [
                                      const Color(0xFF06B6D4),
                                      const Color(0xFF3B82F6),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.item.mediaKind.labelIt,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          'ID: ${widget.item.id}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                        if (widget.item.year.isNotEmpty)
                          Text(
                            '• ${widget.item.year}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        if (widget.item.voteAverage != null &&
                            widget.item.voteAverage! > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFBBF24),
                                size: 15,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                widget.item.voteAverage!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      overview,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Action Buttons Row: Guarda Ora, Salva/Scarica, Salva in Lista
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () => _openPlayer(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(
                    widget.item.mediaKind == MediaKind.movie
                        ? 'Guarda Ora'
                        : 'Guarda S${_selectedSeason}E$_selectedEpisode',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _handleSaveOrDownloadAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(
                    widget.item.mediaKind == MediaKind.movie
                        ? 'Salva / Scarica'
                        : 'Scarica Serie/Ep',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: isSaved
                      ? const Color(0xFFF43F5E).withValues(alpha: 0.2)
                      : const Color(0xFF1E293B),
                ),
                tooltip: isSaved ? 'Rimuovi dalla Lista' : 'Salva nella Lista',
                onPressed: () async {
                  final added =
                      await DownloadService.instance.toggleSaved(widget.item);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          added
                              ? '${widget.item.title} salvato nella tua lista!'
                              : '${widget.item.title} rimosso dalla lista.',
                        ),
                      ),
                    );
                  }
                },
                icon: Icon(
                  isSaved
                      ? Icons.bookmark_added_rounded
                      : Icons.bookmark_add_outlined,
                  color:
                      isSaved ? const Color(0xFFF43F5E) : Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPosterFallback() {
    return Container(
      width: 88,
      height: 128,
      color: const Color(0xFF171E2C),
      alignment: Alignment.center,
      child: const Icon(Icons.movie_rounded, color: Colors.white38, size: 36),
    );
  }

  Widget _buildOptionsToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121722),
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xFF232B3E)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildDropdownChip(
              label: 'Lingua',
              value: _selectedLang,
              items: const {
                'it': '🇮🇹 Italiano',
                'en': '🇬🇧 English',
                'ja': '🇯🇵 Japanese',
              },
              onChanged: (val) {
                if (val == null) return;
                setState(() => _selectedLang = val);
                _loadInitialData();
              },
            ),
            const SizedBox(width: 10),
            _buildDropdownChip(
              label: 'Qualità',
              value: _selectedQuality,
              items: const {
                'best': 'Auto (Migliore)',
                '2160p': '4K (2160p)',
                '1080p': 'Full HD (1080p)',
                '720p': 'HD (720p)',
                '480p': 'SD (480p)',
              },
              onChanged: (val) {
                if (val == null) return;
                setState(() => _selectedQuality = val);
              },
            ),
            const SizedBox(width: 10),
            _buildDropdownChip(
              label: 'Sorgente',
              value: _selectedSource,
              items: const {
                'auto': 'Auto Resolver',
                'vixsrc': 'VixSrc Cloud',
                'animeunity': 'AnimeUnity',
              },
              onChanged: (val) {
                if (val == null) return;
                setState(() => _selectedSource = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownChip({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.containsKey(value) ? value : items.keys.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF232B3E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue,
              dropdownColor: const Color(0xFF171E2C),
              isDense: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              items: items.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Seasons & Episodes (TV / Anime) ─────────────────────────

  Widget _buildEpisodesTab(ScrollController scrollController) {
    if (_isLoadingData) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF06B6D4)),
      );
    }

    if (widget.item.mediaKind == MediaKind.anime) {
      final count =
          _animeEpisodes?.episodesCount ?? widget.item.episodesCount ?? 12;
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Episodi disponibili ($count)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              TextButton.icon(
                onPressed: _showSeriesDownloadModal,
                icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                label: const Text('Scarica Tutti'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(count, (index) {
            final epNum = index + 1;
            final isSelected = _selectedEpisode == epNum;
            return _buildEpisodeRow(
              season: 1,
              episode: epNum,
              title: 'Episodio $epNum',
              isSelected: isSelected,
            );
          }),
        ],
      );
    }

    // TV Series seasons
    final seasons = _downloadInfo?.seasons ??
        [
          const TvSeasonSummary(
            id: 1,
            name: 'Stagione 1',
            seasonNumber: 1,
            episodeCount: 12,
          ),
        ];

    final activeSeason = seasons
            .where((s) => s.seasonNumber == _selectedSeason)
            .firstOrNull ??
        seasons.first;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Season Selector Chips + Season Download Button
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: seasons.map((s) {
              final selected = s.seasonNumber == _selectedSeason;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    'Stagione ${s.seasonNumber} (${s.episodeCount} ep)',
                  ),
                  selected: selected,
                  selectedColor: const Color(0xFF06B6D4),
                  backgroundColor: const Color(0xFF171E2C),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedSeason = s.seasonNumber;
                      _selectedEpisode = 1;
                    });
                    _refreshTorrents();
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${activeSeason.name} • ${activeSeason.episodeCount} Episodi',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: const Color(0xFF38BDF8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () async {
                final count =
                    await DownloadService.instance.enqueueSeasonBatch(
                  mediaId: widget.item.id,
                  title: widget.item.title,
                  mediaKind: MediaKind.tv,
                  seasonNumber: activeSeason.seasonNumber,
                  episodeCount: activeSeason.episodeCount,
                  language: _selectedLang,
                  quality: _selectedQuality,
                  posterUrl: widget.item.posterUrl,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Messa in coda l\'intera Stagione ${activeSeason.seasonNumber} ($count episodi)!',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.downloading_rounded, size: 16),
              label: Text('Scarica Stagione ${activeSeason.seasonNumber}'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(activeSeason.episodeCount.clamp(1, 150), (idx) {
          final epNum = idx + 1;
          return _buildEpisodeRow(
            season: activeSeason.seasonNumber,
            episode: epNum,
            title: 'Episodio $epNum',
            isSelected: _selectedEpisode == epNum,
          );
        }),
      ],
    );
  }

  Widget _buildEpisodeRow({
    required int season,
    required int episode,
    required String title,
    required bool isSelected,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF06B6D4).withValues(alpha: 0.12)
            : const Color(0xFF121722),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF06B6D4)
              : const Color(0xFF232B3E),
        ),
      ),
      child: ListTile(
        onTap: () {
          setState(() {
            _selectedSeason = season;
            _selectedEpisode = episode;
          });
          _refreshTorrents();
        },
        leading: CircleAvatar(
          backgroundColor: isSelected
              ? const Color(0xFF06B6D4)
              : const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          radius: 18,
          child: Text(
            '$episode',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          widget.item.mediaKind == MediaKind.anime
              ? 'AnimeUnity • $_selectedQuality'
              : 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} • $_selectedQuality • ${_selectedLang.toUpperCase()}',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Scarica Episodio MP4',
              icon: const Icon(
                Icons.download_rounded,
                color: Color(0xFF38BDF8),
              ),
              onPressed: () async {
                await DownloadService.instance.enqueueSingle(
                  mediaId: widget.item.id,
                  title: widget.item.title,
                  mediaKind: widget.item.mediaKind,
                  season: season,
                  episode: episode,
                  episodeTitle: title,
                  language: _selectedLang,
                  quality: _selectedQuality,
                  posterUrl: widget.item.posterUrl,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Download avviato: ${widget.item.title} S${season}E$episode',
                      ),
                    ),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Riproduci Ora',
              icon: const Icon(
                Icons.play_circle_fill_rounded,
                color: Color(0xFF06B6D4),
                size: 28,
              ),
              onPressed: () => _openPlayer(season: season, episode: episode),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 2: Torrents P2P Management ─────────────────────────────────

  Widget _buildTorrentsTab(ScrollController scrollController) {
    if (widget.item.mediaKind == MediaKind.anime) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: Color(0xFFFB7185),
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'Gli anime su AnimeUnity usano streaming diretto HLS ad alta velocità.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              const Text(
                'Se cerchi torrent per un anime, cercalo tramite il filtro Film o Serie TV (TMDB/IMDb).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingTorrents) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF06B6D4)),
      );
    }

    final filtered = _torrentQualityFilter == 'all'
        ? _torrents
        : _torrents
            .where((t) => t.quality.label == _torrentQualityFilter)
            .toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final q in ['all', '2160p', '1080p', '720p', '480p'])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(q == 'all' ? 'Tutti' : q.toUpperCase()),
                          selected: _torrentQualityFilter == q,
                          selectedColor: const Color(0xFF06B6D4),
                          backgroundColor: const Color(0xFF171E2C),
                          labelStyle: TextStyle(
                            color: _torrentQualityFilter == q
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                          onSelected: (_) =>
                              setState(() => _torrentQualityFilter = q),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Aggiorna Torrent',
              onPressed: _refreshTorrents,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: const Text(
              'Nessun torrent trovato per questo titolo/episodio con i filtri attuali.',
              style: TextStyle(color: Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...filtered.map(_buildTorrentCard),
      ],
    );
  }

  Widget _buildTorrentCard(TorrentItem torrent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: torrent.cached
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : const Color(0xFF232B3E),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: torrent.quality.badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: torrent.quality.badgeColor),
                ),
                child: Text(
                  torrent.quality.displayBadge,
                  style: TextStyle(
                    color: torrent.quality.badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (torrent.cached)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '⚡ CACHED',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Icon(
                Icons.people_alt_rounded,
                size: 15,
                color: torrent.seeders > 20
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 4),
              Text(
                '${torrent.seeders} seeders',
                style: TextStyle(
                  color: torrent.seeders > 20
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                torrent.formattedSize,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            torrent.filename ?? torrent.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (torrent.sourceIndexer != null)
                Text(
                  '🔗 ${torrent.sourceIndexer}',
                  style:
                      const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              if (torrent.languages.isNotEmpty)
                Text(
                  '🗣️ ${torrent.languages.map((l) => l.toUpperCase()).join(", ")}',
                  style:
                      const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Torrent Actions: Guarda Direttamente, Scarica via Client Torrent, Copia Magnet
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () {
                  // Stream directly in player (or fallback to HLS with same quality)
                  _selectedQuality = torrent.quality.label != 'unknown'
                      ? torrent.quality.label
                      : _selectedQuality;
                  _openPlayer();
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text(
                  'Guarda Ora (HLS)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () async {
                  final launched =
                      await TorrentLauncher.openMagnetInExternalClient(
                          torrent.magnet);
                  if (!launched) {
                    await TorrentLauncher.copyToClipboard(torrent.magnet);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          launched
                              ? 'Magnet aperto nel client Torrent predefinito!'
                              : 'Link Magnet copiato negli appunti!',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.downloading_rounded, size: 16),
                label: const Text(
                  'Scarica Torrent (Magnet)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF28334B)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onPressed: () async {
                  await TorrentLauncher.copyToClipboard(torrent.magnet);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Magnet URI copiato negli appunti!'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Copia Magnet', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 3: HLS Packages & Technical Stream Info ────────────────────

  Widget _buildHlsPackagesTab(ScrollController scrollController) {
    final packages = _downloadInfo?.packages ?? [];
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Pacchetti HLS & Qualità Rilevate dall\'API',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        if (packages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Le tracce HLS verranno estratte automaticamente all\'avvio della riproduzione o del download.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          )
        else
          ...packages.map((pkg) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121722),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF232B3E)),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: pkg.quality.badgeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      pkg.quality.displayBadge,
                      style: TextStyle(
                        color: pkg.quality.badgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pkg.label ?? 'Rendition #${pkg.number}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Audio: ${pkg.audio.length} tracce • Sub: ${pkg.subtitles.length} tracce',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() => _selectedQuality = pkg.quality.label);
                      _openPlayer();
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Riproduci'),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _showFfmpegCommandDialog,
          icon: const Icon(Icons.terminal_rounded),
          label: const Text('Genera Comando FFmpeg Offload (?download=cmd)'),
        ),
      ],
    );
  }
}
