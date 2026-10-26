import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onlystream/models/video_model.dart';
import 'package:onlystream/screens/media_detail_sheet.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/services/download_service.dart';
import 'package:onlystream/services/server_config_service.dart';
import 'package:onlystream/services/video_service.dart';
import 'package:onlystream/utils/torrent_launcher.dart';
import 'package:onlystream/widgets/server_quick_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedNavIndex = 0;

  // Search State
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchFilter = 'all'; // 'all', 'movie', 'tv', 'anime'
  bool _isSearching = false;
  List<UnifiedSearchResult> _searchResults = [];

  // Torrent Hub State
  final TextEditingController _torrentIdController =
      TextEditingController(text: '1396');
  MediaKind _torrentMediaKind = MediaKind.tv;
  int _torrentSeason = 1;
  int _torrentEpisode = 1;
  String _torrentQualityFilter = 'all';
  bool _isLoadingHubTorrents = false;
  List<TorrentItem> _hubTorrents = [];

  // Featured / Trending Catalog
  static const List<UnifiedSearchResult> _featuredItems = [
    UnifiedSearchResult(
      id: 1396,
      title: 'Breaking Bad',
      mediaKind: MediaKind.tv,
      releaseDate: '2008-01-20',
      voteAverage: 8.9,
      posterUrl:
          'https://image.tmdb.org/t/p/w500/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg',
      backdropUrl:
          'https://image.tmdb.org/t/p/w1280/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg',
      overview:
          'Un professore di chimica scopre di avere un cancro terminale e inizia a produrre metanfetamina con un suo ex studente.',
    ),
    UnifiedSearchResult(
      id: 872585,
      title: 'Oppenheimer',
      mediaKind: MediaKind.movie,
      releaseDate: '2023-07-19',
      voteAverage: 8.1,
      posterUrl:
          'https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
      backdropUrl:
          'https://image.tmdb.org/t/p/w1280/fm6KqXpk3M2HVveHwCrBSSBaO0V.jpg',
      overview:
          'La storia del fisico americano J. Robert Oppenheimer e del suo ruolo nello sviluppo della bomba atomica.',
    ),
    UnifiedSearchResult(
      id: 66732,
      title: 'Stranger Things',
      mediaKind: MediaKind.tv,
      releaseDate: '2016-07-15',
      voteAverage: 8.6,
      posterUrl:
          'https://image.tmdb.org/t/p/w500/uOOtwVbSr4QDjAGIifLDwpb2Pdl.jpg',
      backdropUrl:
          'https://image.tmdb.org/t/p/w1280/56v2KjBlU4XaOv9rVYEQypROD7P.jpg',
      overview:
          'Quando un ragazzo scompare in una piccola cittadina, un gruppo di amici scopre esperimenti segreti e forze soprannaturali.',
    ),
    UnifiedSearchResult(
      id: 157336,
      title: 'Interstellar',
      mediaKind: MediaKind.movie,
      releaseDate: '2014-11-05',
      voteAverage: 8.4,
      posterUrl:
          'https://image.tmdb.org/t/p/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg',
      backdropUrl:
          'https://image.tmdb.org/t/p/w1280/xJHokMbljvjADYdit5fK5VQsXEG.jpg',
      overview:
          'Un gruppo di esploratori viaggia attraverso un wormhole nello spazio per garantire la sopravvivenza dell\'umanità.',
    ),
    UnifiedSearchResult(
      id: 550,
      title: 'Fight Club',
      mediaKind: MediaKind.movie,
      releaseDate: '1999-10-15',
      voteAverage: 8.4,
      posterUrl:
          'https://image.tmdb.org/t/p/w500/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg',
      backdropUrl:
          'https://image.tmdb.org/t/p/w1280/hZkgoQYus5vegHoetLkCJzb17zJ.jpg',
      overview:
          'Un impiegato insonne e un eccentrico venditore di sapone fondano un fight club clandestino che si trasforma in qualcosa di molto più grande.',
    ),
    UnifiedSearchResult(
      id: 27205,
      title: 'Inception',
      mediaKind: MediaKind.movie,
      releaseDate: '2010-07-15',
      voteAverage: 8.4,
      posterUrl:
          'https://image.tmdb.org/t/p/w500/oYuLEt3zVCKq57qu2F8dT7NIa6f.jpg',
      backdropUrl:
          'https://image.tmdb.org/t/p/w1280/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg',
      overview:
          'Dom Cobb possiede una qualifica speciale: è in grado di inserirsi nei sogni altrui per prelevare i segreti nascosti nel più profondo del subconscio.',
    ),
    UnifiedSearchResult(
      id: 4290,
      title: 'Solo Leveling',
      mediaKind: MediaKind.anime,
      releaseDate: '2024',
      episodesCount: 12,
      isDubbedIta: true,
      overview:
          'Sung Jin-Woo, il cacciatore più debole dell\'umanità, ottiene il potere unico di salire di livello senza limiti.',
    ),
    UnifiedSearchResult(
      id: 1399,
      title: 'Il Trono di Spade',
      mediaKind: MediaKind.tv,
      releaseDate: '2011-04-17',
      voteAverage: 8.4,
      posterUrl:
          'https://image.tmdb.org/t/p/w500/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg',
      backdropUrl:
          'https://image.tmdb.org/t/p/w1280/2OMB0ynKlyIenMJWI2Dy9IWT4c.jpg',
      overview:
          'Nove famiglie nobili lottano per il controllo delle terre mitiche di Westeros, mentre un antico nemico ritorna.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    ServerConfigService.instance.addListener(_onServiceChanged);
    DownloadService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _torrentIdController.dispose();
    ServerConfigService.instance.removeListener(_onServiceChanged);
    DownloadService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchQueryChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() => _isSearching = true);
    final results = await VideoService.searchAll(
      query: q,
      filter: _searchFilter,
      language: ServerConfigService.instance.defaultLanguage,
    );
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _loadHubTorrents() async {
    final rawId = _torrentIdController.text.trim();
    if (rawId.isEmpty) return;
    setState(() => _isLoadingHubTorrents = true);
    final list = await VideoService.fetchTorrents(
      kind: _torrentMediaKind,
      rawId: rawId,
      season: _torrentSeason,
      episode: _torrentEpisode,
      language: ServerConfigService.instance.defaultLanguage,
    );
    if (mounted) {
      setState(() {
        _hubTorrents = list;
        _isLoadingHubTorrents = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 820;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      appBar: _buildTopAppBar(),
      body: Row(
        children: [
          if (isWide) _buildNavigationRail(),
          Expanded(
            child: IndexedStack(
              index: _selectedNavIndex,
              children: [
                _buildExploreAndSearchView(),
                _buildTorrentHubView(),
                _buildDownloadsAndSavedView(),
                _buildServerSettingsView(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide ? null : _buildBottomNavBar(),
    );
  }

  PreferredSizeWidget _buildTopAppBar() {
    final serverConfig = ServerConfigService.instance;
    final status = serverConfig.status;
    final activeDl = DownloadService.instance.activeDownloadsCount;

    return AppBar(
      backgroundColor: const Color(0xFF121722),
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF06B6D4),
                  Color(0xFF3B82F6),
                  Color(0xFF8B5CF6),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OnlyStream',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'EasyStream API Client • HLS & Torrent P2P',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (activeDl > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              backgroundColor: const Color(0xFF06B6D4).withValues(alpha: 0.15),
              side: const BorderSide(color: Color(0xFF06B6D4)),
              avatar: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF06B6D4),
                ),
              ),
              label: Text(
                '$activeDl Download',
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => setState(() => _selectedNavIndex = 2),
            ),
          ),

        // Quick Server IP Status Pill
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => ServerQuickDialog.show(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (status.isOnline
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF43F5E))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: status.isOnline
                      ? const Color(0xFF10B981).withValues(alpha: 0.5)
                      : const Color(0xFFF43F5E).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status.isOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF43F5E),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    serverConfig.baseUrl
                        .replaceFirst('http://', '')
                        .replaceFirst('https://', ''),
                    style: TextStyle(
                      color: status.isOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF43F5E),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.edit_location_alt_rounded,
                    size: 14,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationRail() {
    final activeDl = DownloadService.instance.activeDownloadsCount;
    return NavigationRail(
      backgroundColor: const Color(0xFF121722),
      selectedIndex: _selectedNavIndex,
      onDestinationSelected: (idx) {
        setState(() => _selectedNavIndex = idx);
        if (idx == 1 && _hubTorrents.isEmpty) {
          _loadHubTorrents();
        }
      },
      labelType: NavigationRailLabelType.all,
      selectedIconTheme: const IconThemeData(color: Color(0xFF06B6D4)),
      unselectedIconTheme: const IconThemeData(color: Color(0xFF94A3B8)),
      selectedLabelTextStyle: const TextStyle(
        color: Color(0xFF38BDF8),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
      ),
      destinations: [
        const NavigationRailDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore_rounded),
          label: Text('Esplora & Cerca'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.hub_outlined),
          selectedIcon: Icon(Icons.hub_rounded),
          label: Text('Torrent P2P'),
        ),
        NavigationRailDestination(
          icon: Badge(
            isLabelVisible: activeDl > 0,
            label: Text('$activeDl'),
            child: const Icon(Icons.download_for_offline_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: activeDl > 0,
            label: Text('$activeDl'),
            child: const Icon(Icons.download_for_offline_rounded),
          ),
          label: const Text('Scaricati & Lista'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.settings_ethernet_rounded),
          selectedIcon: Icon(Icons.dns_rounded),
          label: Text('Server IP'),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    final activeDl = DownloadService.instance.activeDownloadsCount;
    return NavigationBar(
      backgroundColor: const Color(0xFF121722),
      selectedIndex: _selectedNavIndex,
      indicatorColor: const Color(0xFF06B6D4).withValues(alpha: 0.2),
      onDestinationSelected: (idx) {
        setState(() => _selectedNavIndex = idx);
        if (idx == 1 && _hubTorrents.isEmpty) {
          _loadHubTorrents();
        }
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore_rounded, color: Color(0xFF06B6D4)),
          label: 'Cerca',
        ),
        const NavigationDestination(
          icon: Icon(Icons.hub_outlined),
          selectedIcon: Icon(Icons.hub_rounded, color: Color(0xFF06B6D4)),
          label: 'Torrent',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: activeDl > 0,
            label: Text('$activeDl'),
            child: const Icon(Icons.download_for_offline_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: activeDl > 0,
            label: Text('$activeDl'),
            child: const Icon(
              Icons.download_for_offline_rounded,
              color: Color(0xFF06B6D4),
            ),
          ),
          label: 'Scaricati',
        ),
        const NavigationDestination(
          icon: Icon(Icons.dns_outlined),
          selectedIcon: Icon(Icons.dns_rounded, color: Color(0xFF06B6D4)),
          label: 'Server IP',
        ),
      ],
    );
  }

  // ── VIEW 0: Explore & Unified Search (TMDB + AnimeUnity) ──────────

  Widget _buildExploreAndSearchView() {
    final hasSearchQuery = _searchController.text.trim().length >= 2;
    final history = DownloadService.instance.watchHistory;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Unified Search Bar Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF161C2A), Color(0xFF121722)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF232B3E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ricerca Unificata (Film, Serie TV, Anime o ID TMDB/IMDb)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                          _isSearching = false;
                        });
                      },
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      label: const Text('Pulisci'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: _onSearchQueryChanged,
                onSubmitted: _executeSearch,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText:
                      'Cerca es. Breaking Bad, Oppenheimer, Solo Leveling, 1396, tt0903747...',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF0A0D14),
                  prefixIcon: const Icon(
                    Icons.manage_search_rounded,
                    color: Color(0xFF06B6D4),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFF38BDF8),
                    ),
                    onPressed: () => _executeSearch(_searchController.text),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF232B3E)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF38BDF8),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Filter Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('all', '🌐 Tutti (TMDB + Anime)'),
                  _buildFilterChip('movie', '🎬 Solo Film'),
                  _buildFilterChip('tv', '📺 Solo Serie TV'),
                  _buildFilterChip('anime', '⚡ Solo Anime (AnimeUnity)'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Search Results Grid if searching
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF06B6D4)),
            ),
          )
        else if (hasSearchQuery) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Risultati della ricerca (${_searchResults.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_searchResults.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF121722),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF232B3E)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 48,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nessun risultato trovato.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Verifica che il server EasyStream API (${ServerConfigService.instance.baseUrl}) sia attivo e raggiungibile.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            _buildMediaGrid(_searchResults),
        ] else ...[
          // Hero Spotlight Banner
          _buildHeroSpotlight(_featuredItems.first),
          const SizedBox(height: 26),

          // Continue Watching History if available
          if (history.isNotEmpty) ...[
            const Text(
              '⏯️ Continua a Guardare',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: history.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final v = history[idx];
                  return _buildHistoryCard(v);
                },
              ),
            ),
            const SizedBox(height: 26),
          ],

          // Featured Catalog Grid
          const Row(
            children: [
              Icon(Icons.local_fire_department_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text(
                'Titoli Consigliati & Popolari',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildMediaGrid(_featuredItems),
        ],
      ],
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final selected = _searchFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFF06B6D4),
      backgroundColor: const Color(0xFF0A0D14),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF94A3B8),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      onSelected: (_) {
        setState(() => _searchFilter = key);
        if (_searchController.text.trim().length >= 2) {
          _executeSearch(_searchController.text);
        }
      },
    );
  }

  Widget _buildHeroSpotlight(UnifiedSearchResult hero) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF232B3E)),
        image: hero.backdropUrl != null
            ? DecorationImage(
                image: NetworkImage(hero.backdropUrl!),
                fit: BoxFit.cover,
                onError: (_, _) {},
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.65),
                  BlendMode.darken,
                ),
              )
            : null,
        gradient: const LinearGradient(
          colors: [Color(0xFF161E2E), Color(0xFF0E131F)],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF06B6D4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'IN EVIDENZA • STREAM & DOWNLOAD SERIE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hero.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(
              hero.overview ?? '',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.5,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onPressed: () => MediaDetailSheet.show(context, hero),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Guarda / Episodi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onPressed: () => MediaDetailSheet.show(context, hero),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Salva / Scarica Serie'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Video video) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(video: video),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF121722),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF232B3E)),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                image: video.posterUrl != null
                    ? DecorationImage(
                        image: NetworkImage(video.posterUrl!),
                        fit: BoxFit.cover,
                        onError: (_, _) {},
                      )
                    : null,
              ),
              child: const Icon(
                Icons.play_circle_fill_rounded,
                color: Color(0xFF06B6D4),
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.currentEpisode != null
                        ? 'S${video.currentEpisode!.season} • E${video.currentEpisode!.number}'
                        : 'Film',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<UnifiedSearchResult> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (context, index) {
        return _buildMediaCard(items[index]);
      },
    );
  }

  Widget _buildMediaCard(UnifiedSearchResult item) {
    final isSaved =
        DownloadService.instance.isSaved(item.id, item.mediaKind);

    return InkWell(
      onTap: () => MediaDetailSheet.show(context, item),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121722),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF232B3E)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.posterUrl != null && item.posterUrl!.isNotEmpty)
                    Image.network(
                      item.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _buildCardPlaceholder(item),
                    )
                  else
                    _buildCardPlaceholder(item),

                  // Top Badges
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: item.mediaKind == MediaKind.anime
                            ? const Color(0xFFF43F5E)
                            : (item.mediaKind == MediaKind.tv
                                ? const Color(0xFF8B5CF6)
                                : const Color(0xFF06B6D4)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.mediaKind.labelIt,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Quick Save/Download Button on Card
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => MediaDetailSheet.show(context, item),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isSaved
                                ? Icons.bookmark_added_rounded
                                : Icons.download_for_offline_rounded,
                            size: 18,
                            color: isSaved
                                ? const Color(0xFFF43F5E)
                                : const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        item.year.isNotEmpty ? item.year : 'ID ${item.id}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      if (item.voteAverage != null && item.voteAverage! > 0) ...[
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFBBF24),
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          item.voteAverage!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else if (item.episodesCount != null)
                        Text(
                          '${item.episodesCount} ep',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
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
    );
  }

  Widget _buildCardPlaceholder(UnifiedSearchResult item) {
    return Container(
      color: const Color(0xFF171E2C),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.mediaKind == MediaKind.anime
                ? Icons.bolt_rounded
                : Icons.movie_creation_outlined,
            color: const Color(0xFF38BDF8),
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── VIEW 1: Dedicated Torrent P2P Hub (Stream & Download) ──────────

  Widget _buildTorrentHubView() {
    final filtered = _torrentQualityFilter == 'all'
        ? _hubTorrents
        : _hubTorrents
            .where((t) => t.quality.label == _torrentQualityFilter)
            .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF121722),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF232B3E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.hub_rounded, color: Color(0xFF06B6D4)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Centro Gestione Torrent P2P (Il Corsaro Viola / Torrentio)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Cerca torrent per qualsiasi Film o Serie TV tramite TMDB ID o IMDb ID (es. tt0903747) per guardarli direttamente o scaricarli.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<MediaKind>(
                    segments: const [
                      ButtonSegment(
                        value: MediaKind.movie,
                        label: Text('Film'),
                        icon: Icon(Icons.movie_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: MediaKind.tv,
                        label: Text('Serie TV'),
                        icon: Icon(Icons.tv_rounded, size: 16),
                      ),
                    ],
                    selected: {_torrentMediaKind},
                    onSelectionChanged: (s) {
                      setState(() => _torrentMediaKind = s.first);
                      _loadHubTorrents();
                    },
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _torrentIdController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'TMDB o IMDb ID',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFF0A0D14),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => _loadHubTorrents(),
                    ),
                  ),
                  if (_torrentMediaKind == MediaKind.tv) ...[
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue: '$_torrentSeason',
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Stagione',
                          filled: true,
                          fillColor: const Color(0xFF0A0D14),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (v) =>
                            _torrentSeason = int.tryParse(v) ?? 1,
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue: '$_torrentEpisode',
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Episodio',
                          filled: true,
                          fillColor: const Color(0xFF0A0D14),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (v) =>
                            _torrentEpisode = int.tryParse(v) ?? 1,
                      ),
                    ),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _loadHubTorrents,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Cerca Torrent'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Quick Presets
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('Breaking Bad S01E01 (1396)'),
                    onPressed: () {
                      setState(() {
                        _torrentMediaKind = MediaKind.tv;
                        _torrentIdController.text = '1396';
                        _torrentSeason = 1;
                        _torrentEpisode = 1;
                      });
                      _loadHubTorrents();
                    },
                  ),
                  ActionChip(
                    label: const Text('Fight Club (550)'),
                    onPressed: () {
                      setState(() {
                        _torrentMediaKind = MediaKind.movie;
                        _torrentIdController.text = '550';
                      });
                      _loadHubTorrents();
                    },
                  ),
                  ActionChip(
                    label: const Text('Oppenheimer (872585)'),
                    onPressed: () {
                      setState(() {
                        _torrentMediaKind = MediaKind.movie;
                        _torrentIdController.text = '872585';
                      });
                      _loadHubTorrents();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              ' Risultati Torrent (${filtered.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            for (final q in ['all', '2160p', '1080p', '720p'])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(q == 'all' ? 'Tutti' : q.toUpperCase()),
                  selected: _torrentQualityFilter == q,
                  selectedColor: const Color(0xFF06B6D4),
                  onSelected: (_) =>
                      setState(() => _torrentQualityFilter = q),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingHubTorrents)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF06B6D4)),
            ),
          )
        else if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF121722),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Premi "Cerca Torrent" per caricare i flussi P2P dal server API.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          )
        else
          ...filtered.map((t) => _buildHubTorrentTile(t)),
      ],
    );
  }

  Widget _buildHubTorrentTile(TorrentItem torrent) {
    final numericId =
        int.tryParse(_torrentIdController.text.replaceAll('tt', '')) ?? 550;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: torrent.cached
              ? const Color(0xFF10B981).withValues(alpha: 0.45)
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
              const SizedBox(width: 10),
              if (torrent.cached)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Text(
                    '⚡ CACHED',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              Text(
                '👥 ${torrent.seeders} seeders',
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                torrent.formattedSize,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            torrent.filename ?? torrent.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final video = Video(
                    id: numericId,
                    title: torrent.title,
                    type: _torrentMediaKind == MediaKind.tv
                        ? 'series'
                        : 'movie',
                    currentEpisode: _torrentMediaKind == MediaKind.tv
                        ? Episode(
                            season: _torrentSeason,
                            number: _torrentEpisode,
                          )
                        : null,
                    hasNext: _torrentMediaKind == MediaKind.tv,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerScreen(
                        video: video,
                        initialQuality: torrent.quality.label,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                label: const Text('Guarda Direttamente'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                ),
                onPressed: () async {
                  final ok =
                      await TorrentLauncher.openMagnetInExternalClient(
                          torrent.magnet);
                  if (!ok) {
                    await TorrentLauncher.copyToClipboard(torrent.magnet);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Magnet aperto nel client Torrent!'
                              : 'Link Magnet copiato negli appunti!',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.downloading_rounded, size: 18),
                label: const Text('Scarica con Client Torrent'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await TorrentLauncher.copyToClipboard(torrent.magnet);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Magnet copiato negli appunti!'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copia Magnet'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── VIEW 2: Downloads & Saved Library ("Salva / Scarica") ──────────

  Widget _buildDownloadsAndSavedView() {
    final dlService = DownloadService.instance;
    final tasks = dlService.tasks;
    final watchlist = dlService.savedWatchlist;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Downloads Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📥 Gestione Download (Film, Episodi & Serie)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Cartella: ${ServerConfigService.instance.effectiveDownloadDir.path}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => TorrentLauncher.openFolder(
                    ServerConfigService.instance.effectiveDownloadDir.path,
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Apri Cartella'),
                ),
                const SizedBox(width: 8),
                if (tasks.isNotEmpty)
                  TextButton.icon(
                    onPressed: dlService.clearFinishedTasks,
                    icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                    label: const Text('Pulisci Completati'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (tasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF121722),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF232B3E)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  color: Color(0xFF64748B),
                  size: 44,
                ),
                SizedBox(height: 10),
                Text(
                  'Nessun download attivo o completato.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Apri qualsiasi Film, Serie TV o Anime e premi "Salva / Scarica" per scaricare singoli episodi, stagioni intere o tutta la serie!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                ),
              ],
            ),
          )
        else
          ...tasks.map(_buildDownloadTaskCard),

        const SizedBox(height: 30),

        // Saved Watchlist Section
        const Text(
          '🔖 La Mia Lista Salvata',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (watchlist.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF121722),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF232B3E)),
            ),
            child: const Text(
              'Non hai ancora salvato nessun titolo nella tua lista.',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          )
        else
          _buildMediaGrid(watchlist),
      ],
    );
  }

  Widget _buildDownloadTaskCard(DownloadTaskItem task) {
    final (Color badgeColor, String statusText, IconData statusIcon) =
        switch (task.status) {
      DownloadStatus.queued => (
          const Color(0xFFF59E0B),
          'In Coda',
          Icons.schedule_rounded
        ),
      DownloadStatus.downloading => (
          const Color(0xFF06B6D4),
          'In Scaricamento (${task.formattedBytes})',
          Icons.downloading_rounded
        ),
      DownloadStatus.completed => (
          const Color(0xFF10B981),
          'Completato (${task.formattedBytes})',
          Icons.check_circle_rounded
        ),
      DownloadStatus.failed => (
          const Color(0xFFF43F5E),
          'Errore',
          Icons.error_outline_rounded
        ),
      DownloadStatus.cancelled => (
          const Color(0xFF64748B),
          'Annullato',
          Icons.cancel_outlined
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF232B3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: badgeColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      task.subtitle,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              color: Color(0xFF06B6D4),
              backgroundColor: Color(0xFF1E293B),
            ),
          ],
          if (task.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              task.errorMessage!,
              style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (task.status == DownloadStatus.completed)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final offlineVideo = Video(
                      id: task.mediaId,
                      title: '${task.title} (${task.subtitle})',
                      type: task.mediaKind.value,
                      localFilePath: task.filePath,
                    );
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(video: offlineVideo),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Riproduci File Locale'),
                ),
              if (task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.cancelled)
                TextButton.icon(
                  onPressed: () =>
                      DownloadService.instance.retryTask(task.taskId),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Riprova'),
                ),
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.queued)
                TextButton.icon(
                  onPressed: () =>
                      DownloadService.instance.cancelTask(task.taskId),
                  icon: const Icon(
                    Icons.stop_circle_outlined,
                    color: Color(0xFFF43F5E),
                    size: 16,
                  ),
                  label: const Text(
                    'Annulla',
                    style: TextStyle(color: Color(0xFFF43F5E)),
                  ),
                ),
              IconButton(
                tooltip: 'Rimuovi dalla lista',
                onPressed: () =>
                    DownloadService.instance.removeTask(task.taskId),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── VIEW 3: Server IP & Global Preferences ─────────────────────────

  Widget _buildServerSettingsView() {
    final config = ServerConfigService.instance;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF121722),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF232B3E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🌐 Configurazione Server Principale (EasyStream API)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Server attuale: ${config.baseUrl}',
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => ServerQuickDialog.show(context),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Cambia IP / URL del Server'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => config.checkHealth(),
                    icon: const Icon(Icons.network_ping_rounded, size: 18),
                    label: const Text('Test Connessione (/health)'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFF232B3E)),
              const SizedBox(height: 12),
              const Text(
                'Preferenze Predefinite di Streaming & Download',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Lingua Audio Preferita',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Usata per la risoluzione automatica di VixSrc, AnimeUnity e Torrent',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                trailing: DropdownButton<String>(
                  value: config.defaultLanguage,
                  dropdownColor: const Color(0xFF171E2C),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'it', child: Text('🇮🇹 Italiano')),
                    DropdownMenuItem(value: 'en', child: Text('🇬🇧 English')),
                    DropdownMenuItem(value: 'ja', child: Text('🇯🇵 Japanese')),
                  ],
                  onChanged: (v) => config.setPreferences(language: v),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Qualità Video Preferita',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Seleziona la risoluzione predefinita per player HLS e download MP4',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                trailing: DropdownButton<String>(
                  value: config.preferredQuality,
                  dropdownColor: const Color(0xFF171E2C),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(
                        value: 'best', child: Text('Migliore (Auto)')),
                    DropdownMenuItem(value: '2160p', child: Text('4K (2160p)')),
                    DropdownMenuItem(
                        value: '1080p', child: Text('Full HD (1080p)')),
                    DropdownMenuItem(value: '720p', child: Text('HD (720p)')),
                    DropdownMenuItem(value: '480p', child: Text('SD (480p)')),
                  ],
                  onChanged: (v) => config.setPreferences(quality: v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
