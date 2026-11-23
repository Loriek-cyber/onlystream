import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onlystream/models/library.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/screens/media_detail_screen.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/media_cards.dart';

class LibraryScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;

  const LibraryScreen({
    super.key,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ApiClient _apiClient;
  late final ConfigService _config;
  late final LibraryService _library;

  WatchStatus _selectedSegment = WatchStatus.watching;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;
    _library.addListener(_onLibraryChanged);
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    super.dispose();
  }

  List<LibraryItemView> _itemsForSegment() {
    switch (_selectedSegment) {
      case WatchStatus.watching:
        return _library.continueWatching;
      case WatchStatus.saved:
        return _library.saved;
      case WatchStatus.completed:
        return _library.completed;
    }
  }

  void _openDetail(LibraryItemView item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailScreen(
          summary: MediaSummary.fromLibrary(item),
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
        ),
      ),
    );
  }

  void _resumePlayback(LibraryItemView item) {
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

  Future<void> _moveStatus(LibraryItemView item, WatchStatus status) async {
    await _library.setStatus(
      kind: item.kind,
      id: item.id,
      isAnime: item.isAnime,
      title: item.title,
      poster: item.poster,
      backdrop: item.backdrop,
      year: item.year,
      status: status,
      currentSeason: item.currentSeason,
      currentEpisode: item.currentEpisode,
      preferredLang: item.preferredLang,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsForSegment();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<WatchStatus>(
              segments: const [
                ButtonSegment(
                  value: WatchStatus.watching,
                  label: Text('In corso'),
                ),
                ButtonSegment(
                  value: WatchStatus.saved,
                  label: Text('Salvati'),
                ),
                ButtonSegment(
                  value: WatchStatus.completed,
                  label: Text('Completati'),
                ),
              ],
              selected: {_selectedSegment},
              onSelectionChanged: (selection) {
                setState(() => _selectedSegment = selection.first);
              },
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.textPrimary,
            backgroundColor: AppColors.surface,
            onRefresh: () => _library.refresh(lang: _config.language),
            child: items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _emptyLabel(),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _LibraryItemTile(
                        item: item,
                        showResume: _selectedSegment == WatchStatus.watching,
                        onTap: () => _selectedSegment == WatchStatus.watching
                            ? _resumePlayback(item)
                            : _openDetail(item),
                        onOpenDetail: () => _openDetail(item),
                        onResume: () => _resumePlayback(item),
                        onMoveStatus: (status) =>
                            unawaited(_moveStatus(item, status)),
                        onRemove: () =>
                            unawaited(_library.remove(item.kind, item.id)),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  String _emptyLabel() {
    switch (_selectedSegment) {
      case WatchStatus.watching:
        return 'Nessuna riproduzione in corso.';
      case WatchStatus.saved:
        return 'Nessun titolo salvato.';
      case WatchStatus.completed:
        return 'Nessun titolo completato.';
    }
  }
}

class _LibraryItemTile extends StatelessWidget {
  final LibraryItemView item;
  final bool showResume;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final VoidCallback onResume;
  final void Function(WatchStatus status) onMoveStatus;
  final VoidCallback onRemove;

  const _LibraryItemTile({
    required this.item,
    required this.showResume,
    required this.onTap,
    required this.onOpenDetail,
    required this.onResume,
    required this.onMoveStatus,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final kindLabel = item.isAnime
        ? 'Anime'
        : (item.kind == MediaKind.tv ? 'Serie TV' : 'Film');
    final meta = <String>[
      kindLabel,
      if (item.year != null && item.year!.isNotEmpty) item.year!,
      if (item.episodeLabel != null) item.episodeLabel!,
    ].join(' · ');

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
          children: [
            SizedBox(
              width: 56,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaNetworkImage(
                        url: item.poster ?? item.backdrop,
                        fallbackIcon: item.kind == MediaKind.tv
                            ? Icons.tv_outlined
                            : Icons.movie_outlined,
                      ),
                      if (item.progressRatio > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SizedBox(
                            height: 3,
                            child: LinearProgressIndicator(
                              value: item.progressRatio,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                    ],
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
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (item.hasNewEpisodes) ...[
                    const SizedBox(height: 5),
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
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            item.newEpisodesCount > 0
                                ? 'Nuovi episodi (${item.newEpisodesCount})'
                                : 'Nuovi episodi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (showResume)
              IconButton(
                tooltip: 'Riprendi',
                icon: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.textPrimary,
                ),
                onPressed: onResume,
              ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppColors.textSecondary,
              ),
              color: AppColors.surfaceElevated,
              onSelected: (value) {
                switch (value) {
                  case 'detail':
                    onOpenDetail();
                  case 'watching':
                    onMoveStatus(WatchStatus.watching);
                  case 'saved':
                    onMoveStatus(WatchStatus.saved);
                  case 'completed':
                    onMoveStatus(WatchStatus.completed);
                  case 'remove':
                    onRemove();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'detail',
                  child: Text('Dettagli'),
                ),
                if (item.status != WatchStatus.watching)
                  const PopupMenuItem(
                    value: 'watching',
                    child: Text('Sposta in In corso'),
                  ),
                if (item.status != WatchStatus.saved)
                  const PopupMenuItem(
                    value: 'saved',
                    child: Text('Sposta in Salvati'),
                  ),
                if (item.status != WatchStatus.completed)
                  const PopupMenuItem(
                    value: 'completed',
                    child: Text('Segna come completato'),
                  ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Rimuovi'),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
