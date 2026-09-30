import 'package:flutter/material.dart';
import 'package:onlystream/models/video/movie_model.dart';
import 'package:onlystream/models/video/tv_show_model.dart';
import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/screens/film_selector_screen.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/screens/video_screen.dart';
import 'package:onlystream/services/api/api.dart';
import 'package:onlystream/test/test_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Crea lo stato associato alla schermata principale HomeScreen.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `State<HomeScreen>`: Nuova istanza dello stato _HomeScreenState.
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<VideoModel> _trending = [];
  List<MovieModel> _popularMovies = [];
  List<MovieModel> _nowPlayingMovies = [];
  List<TvShowModel> _popularSeries = [];
  List<TvShowModel> _newSeries = [];
  List<TvShowModel> _topRatedSeries = [];
  VideoModel? _featuredVideo;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedCategory = 'Tutti';

  /// Inizializza lo stato del widget avviando il recupero concorrente di tutte le sezioni di discovery.
  /// Riceve: Nessun parametro.
  /// Ritorna: void.
  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  /// Recupera contemporaneamente i dati da tutti gli endpoint di DiscoveryApi con fallback a TestData in caso di errore.
  /// Riceve:
  ///   - `isRefresh` (bool, default false): Flag che indica se il caricamento deriva da un pull-to-refresh.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _loadAllData({bool isRefresh = false}) async {
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final trendingFuture = DiscoveryApi.getTrending();
      final popMoviesFuture = DiscoveryApi.getPopularMovies();
      final nowMoviesFuture = DiscoveryApi.getNowPlayingMovies();
      final popSeriesFuture = DiscoveryApi.getPopularSeries();
      final newSeriesFuture = DiscoveryApi.getNewSeries();
      final topRatedSeriesFuture = DiscoveryApi.getTopRatedSeries();

      final trendingList = await trendingFuture;
      final popMovies = await popMoviesFuture;
      final nowMovies = await nowMoviesFuture;
      final popSeries = await popSeriesFuture;
      final newSer = await newSeriesFuture;
      final topSer = await topRatedSeriesFuture;

      if (!mounted) return;

      final allEmpty = trendingList.isEmpty &&
          popMovies.isEmpty &&
          nowMovies.isEmpty &&
          popSeries.isEmpty &&
          newSer.isEmpty &&
          topSer.isEmpty;

      if (allEmpty) {
        final fallbackList = [
          TestData.breakingBadSeries,
          TestData.oppenheimer,
          TestData.strangerThings,
        ];
        setState(() {
          _trending = fallbackList;
          _popularMovies = [TestData.oppenheimer];
          _nowPlayingMovies = [TestData.oppenheimer];
          _popularSeries = [
            TestData.breakingBadSeries,
            TestData.strangerThings,
          ];
          _newSeries = [TestData.strangerThings];
          _topRatedSeries = [TestData.breakingBadSeries];
          _featuredVideo = TestData.breakingBadSeries;
          _isLoading = false;
        });
        return;
      }

      VideoModel? hero;
      if (trendingList.isNotEmpty) {
        hero = trendingList.first;
      } else if (popMovies.isNotEmpty) {
        hero = popMovies.first;
      } else if (popSeries.isNotEmpty) {
        hero = popSeries.first;
      }

      setState(() {
        _trending = trendingList;
        _popularMovies = popMovies;
        _nowPlayingMovies = nowMovies;
        _popularSeries = popSeries;
        _newSeries = newSer;
        _topRatedSeries = topSer;
        _featuredVideo = hero;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final fallbackList = [
        TestData.breakingBadSeries,
        TestData.oppenheimer,
        TestData.strangerThings,
      ];
      setState(() {
        _trending = fallbackList;
        _popularMovies = [TestData.oppenheimer];
        _nowPlayingMovies = [TestData.oppenheimer];
        _popularSeries = [
          TestData.breakingBadSeries,
          TestData.strangerThings,
        ];
        _newSeries = [TestData.strangerThings];
        _topRatedSeries = [TestData.breakingBadSeries];
        _featuredVideo = TestData.breakingBadSeries;
        _isLoading = false;
        _errorMessage = 'Impossibile connettersi al server locale. Visualizzazione dati di test.';
      });
    }
  }

  /// Apre la schermata di ricerca globale FilmSelectorScreen.
  /// Riceve: Nessun parametro.
  /// Ritorna: void.
  void _navigateToSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FilmSelectorScreen()),
    );
  }

  /// Naviga alla schermata di dettaglio VideoScreen del video selezionato.
  /// Riceve:
  ///   - `video` (VideoModel): Contenuto multimediale da visualizzare.
  /// Ritorna: void.
  void _navigateToVideoScreen(VideoModel video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoScreen(video: video),
      ),
    );
  }

  /// Avvia direttamente la riproduzione del video selezionato aprendo VideoPlayerScreen.
  /// Riceve:
  ///   - `video` (VideoModel): Contenuto multimediale da riprodurre.
  /// Ritorna: void.
  void _playVideo(VideoModel video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          video: video,
          initialSeason: 1,
          initialEpisode: 1,
        ),
      ),
    );
  }

  /// Costruisce la vista principale dell'applicazione con scorrimento verticale e supporto per pull-to-refresh.
  /// Riceve:
  ///   - `context` (BuildContext): Contesto dell'albero dei widget.
  /// Ritorna:
  ///   - `Widget`: Struttura visuale Scaffold contenente la Home in stile Netflix.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: _isLoading
          ? _buildLoadingView()
          : RefreshIndicator(
              color: const Color(0xFFE50914),
              backgroundColor: const Color(0xFF1E1E1E),
              onRefresh: () => _loadAllData(isRefresh: true),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildHeader(),
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCategoryFilters(),
                        if (_featuredVideo != null) _buildHeroBanner(),
                        const SizedBox(height: 12),
                        if (_errorMessage != null)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(229, 9, 20, 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE50914).withAlpha(80)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Color(0xFFE50914), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_selectedCategory == 'Tutti' || _selectedCategory == 'Film') ...[
                          if (_trending.isNotEmpty) ...[
                            _buildSectionHeader('Di Tendenza Oggi', Icons.local_fire_department),
                            _buildVideoCarousel(_trending),
                          ],
                          if (_popularMovies.isNotEmpty) ...[
                            _buildSectionHeader('Film Popolari', Icons.movie),
                            _buildVideoCarousel(_popularMovies),
                          ],
                          if (_nowPlayingMovies.isNotEmpty) ...[
                            _buildSectionHeader('Al Cinema & Nuove Uscite', Icons.new_releases),
                            _buildVideoCarousel(_nowPlayingMovies),
                          ],
                        ],
                        if (_selectedCategory == 'Tutti' || _selectedCategory == 'Serie TV') ...[
                          if (_popularSeries.isNotEmpty) ...[
                            _buildSectionHeader('Serie TV Più Viste', Icons.tv),
                            _buildVideoCarousel(_popularSeries),
                          ],
                          if (_newSeries.isNotEmpty) ...[
                            _buildSectionHeader('Nuove Serie TV in Onda', Icons.live_tv),
                            _buildVideoCarousel(_newSeries),
                          ],
                          if (_topRatedSeries.isNotEmpty) ...[
                            _buildSectionHeader('Serie TV Più Votate', Icons.star),
                            _buildVideoCarousel(_topRatedSeries),
                          ],
                        ],
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Costruisce la barra di intestazione superiore collassabile con il logo e l'azione di ricerca.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: SliverAppBar personalizzata con brand e pulsanti di utilità.
  Widget _buildHeader() {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF0F0F0F).withAlpha(240),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE50914), Color(0xFFB81D24)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'ONLYSTREAM',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white70),
          tooltip: 'Aggiorna catalogo',
          onPressed: () => _loadAllData(isRefresh: true),
        ),
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white, size: 26),
          tooltip: 'Cerca film e serie TV',
          onPressed: _navigateToSearch,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Costruisce la barra dei filtri di categoria (Tutti, Film, Serie TV) per organizzare la vista.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Contenitore con pulsanti ChoiceChip a scorrimento orizzontale.
  Widget _buildCategoryFilters() {
    final categories = ['Tutti', 'Film', 'Serie TV'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              selected: isSelected,
              selectedColor: const Color(0xFFE50914),
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : Colors.white12,
                ),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCategory = cat);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Costruisce il banner hero in evidenza ispirato alle interfacce di Netflix e Apple TV+.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Sezione visiva di testa con poster a schermo largo, titolo, badge e pulsanti di azione.
  Widget _buildHeroBanner() {
    final video = _featuredVideo!;
    final isSeries = video is TvShowModel || video.getType() == 'serie';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      height: 380,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.7),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video.url_image.isNotEmpty)
            Image.network(
              video.url_image,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFF1B1B1B),
                child: const Icon(Icons.movie, size: 70, color: Colors.white24),
              ),
            )
          else
            Container(
              color: const Color(0xFF1B1B1B),
              child: const Icon(Icons.movie, size: 70, color: Colors.white24),
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(0, 0, 0, 0.2),
                  Color.fromRGBO(0, 0, 0, 0.4),
                  Color.fromRGBO(15, 15, 15, 0.95),
                  Color(0xFF0F0F0F),
                ],
                stops: [0.0, 0.4, 0.85, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isSeries ? 'SERIE TV' : 'FILM',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 255, 255, 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '#1 IN EVIDENZA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  video.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (video.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    video.description,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _playVideo(video),
                        icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24),
                        label: const Text(
                          'Riproduci',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _navigateToVideoScreen(video),
                        icon: const Icon(Icons.info_outline, color: Colors.white, size: 22),
                        label: const Text(
                          'Dettagli',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white38),
                          backgroundColor: const Color.fromRGBO(255, 255, 255, 0.1),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
    );
  }

  /// Costruisce l'intestazione grafica per ciascuna sezione del catalogo.
  /// Riceve:
  ///   - `title` (String): Titolo descrittivo della categoria (es. 'Film Popolari').
  ///   - `icon` (IconData): Icona rappresentativa del genere o della categoria.
  /// Ritorna:
  ///   - `Widget`: Riga decorativa con icona colorata e titolo in grassetto.
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFE50914), size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Costruisce una riga orizzontale scorrevole (carousel) di card di locandine per i contenuti.
  /// Riceve:
  ///   - `items` (`List<VideoModel>`): Lista di elementi video da visualizzare.
  /// Ritorna:
  ///   - `Widget`: ListView a scorrimento orizzontale contenente le card dei video.
  Widget _buildVideoCarousel(List<VideoModel> items) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final video = items[index];
          return _buildVideoCard(video);
        },
      ),
    );
  }

  /// Costruisce la singola card cliccabile con locandina, badge di tipologia e titolo troncato.
  /// Riceve:
  ///   - `video` (VideoModel): Elemento del film o serie TV rappresentato.
  /// Ritorna:
  ///   - `Widget`: Elemento visivo interattivo che naviga a VideoScreen al tap.
  Widget _buildVideoCard(VideoModel video) {
    final isSeries = video is TvShowModel || video.getType() == 'serie';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _navigateToVideoScreen(video),
      child: SizedBox(
        width: 135,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.4),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video.url_image.isNotEmpty)
                      Image.network(
                        video.url_image,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFF1E1E1E),
                          child: Icon(
                            isSeries ? Icons.tv : Icons.movie,
                            color: Colors.white24,
                            size: 40,
                          ),
                        ),
                      )
                    else
                      Container(
                        color: const Color(0xFF1E1E1E),
                        child: Icon(
                          isSeries ? Icons.tv : Icons.movie,
                          color: Colors.white24,
                          size: 40,
                        ),
                      ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSeries
                              ? const Color.fromRGBO(229, 9, 20, 0.9)
                              : const Color.fromRGBO(0, 0, 0, 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isSeries ? 'TV' : 'FILM',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Costruisce l'indicatore di caricamento a tutto schermo durante il fetching iniziale.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Schermata con indicatore circolare rosso e logo ONLYSTREAM.
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Color(0xFFE50914),
            strokeWidth: 3,
          ),
          SizedBox(height: 20),
          Text(
            'Caricamento OnlyStream...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
