import 'dart:async';
import 'package:flutter/material.dart';
import 'package:onlystream/models/video/tv_show_model.dart';
import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/screens/video_screen.dart';
import 'package:onlystream/services/api/api.dart';
import 'package:onlystream/test/test_player.dart';

class FilmSelectorScreen extends StatefulWidget {
  const FilmSelectorScreen({super.key});

  /// Crea lo stato associato alla schermata di selezione contenuti.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `State<FilmSelectorScreen>`: Nuova istanza di _FilmSelectorScreenState.
  @override
  State<FilmSelectorScreen> createState() => _FilmSelectorScreenState();
}

class _FilmSelectorScreenState extends State<FilmSelectorScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<VideoModel> _videos = [];
  List<VideoModel> _initialVideos = [];
  bool _isLoading = false;
  String _currentQuery = '';

  List<VideoModel> get _fallbackVideos => [
        TestData.breakingBadSeries,
        TestData.oppenheimer,
        TestData.strangerThings,
      ];

  /// Inizializza lo stato del widget e avvia il recupero del catalogo iniziale.
  /// Riceve: Nessun parametro.
  /// Ritorna: void.
  @override
  void initState() {
    super.initState();
    _loadInitialCatalog();
  }

  /// Rilascia le risorse occupate dal controller di testo e dal timer di debounce.
  /// Riceve: Nessun parametro.
  /// Ritorna: void.
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Recupera i contenuti di tendenza dal backend o applica il catalogo locale di fallback se il server non è raggiungibile.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _loadInitialCatalog() async {
    setState(() => _isLoading = true);
    final trending = await DiscoveryApi.getTrending();
    if (!mounted) return;

    setState(() {
      if (trending.isNotEmpty) {
        _initialVideos = trending;
        _videos = trending;
      } else {
        _initialVideos = _fallbackVideos;
        _videos = _fallbackVideos;
      }
      _isLoading = false;
    });
  }

  /// Applica un debounce di 450 millisecondi alla digitazione dell'utente per evitare chiamate API ad ogni singolo carattere.
  /// Riceve:
  ///   - `query` (String): Testo digitato all'interno del campo di ricerca.
  /// Ritorna: void.
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _currentQuery = '';
        _videos = _initialVideos;
        _isLoading = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _performSearch(trimmed);
    });
  }

  /// Interroga l'endpoint di ricerca SearchApi con la query inserita e aggiorna la griglia.
  /// Riceve:
  ///   - `query` (String): Stringa di ricerca da trasmettere al server.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
      _currentQuery = query;
    });

    final results = await SearchApi.search(query);
    if (!mounted) return;

    setState(() {
      _videos = results;
      _isLoading = false;
    });
  }

  /// Ripristina lo stato iniziale della ricerca cancellando il testo e ricaricando i contenuti di tendenza.
  /// Riceve: Nessun parametro.
  /// Ritorna: void.
  void _clearSearch() {
    _searchController.clear();
    _debounceTimer?.cancel();
    setState(() {
      _currentQuery = '';
      _videos = _initialVideos;
      _isLoading = false;
    });
  }

  /// Costruisce l'albero visivo principale con la testata in stile streaming e la griglia dei poster.
  /// Riceve:
  ///   - `context` (BuildContext): Contesto dell'albero dei widget.
  /// Ritorna:
  ///   - `Widget`: Struttura Scaffold scura con AppBar, barra di ricerca e griglia.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red[700],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ONLY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'STREAM',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchBar(),
          _buildSectionHeader(),
          Expanded(
            child: _buildBodyContent(),
          ),
        ],
      ),
    );
  }

  /// Genera la barra di ricerca posizionata nella parte superiore con sfondo scuro ed icone dedicate.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Barra di ricerca con TextField e pulsante clear dinamico.
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white12),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          cursorColor: Colors.red,
          decoration: InputDecoration(
            hintText: 'Cerca film, serie TV, anime...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 15),
            prefixIcon: const Icon(Icons.search, color: Colors.white60),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white60),
                    onPressed: _clearSearch,
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  /// Genera il titolo informativo della sezione attiva (tendenze o risultati di ricerca con conteggio).
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Testata della sezione con stile tipografico moderno.
  Widget _buildSectionHeader() {
    final title = _currentQuery.isNotEmpty
        ? 'Risultati per "$_currentQuery"'
        : 'In evidenza & Tendenze';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          if (!_isLoading && _videos.isNotEmpty)
            Text(
              '${_videos.length} titoli',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }

  /// Determina se mostrare l'indicatore di caricamento, lo stato di lista vuota o la griglia dei contenuti.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Contenuto principale del corpo della schermata.
  Widget _buildBodyContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.red,
          strokeWidth: 3,
        ),
      );
    }

    if (_videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_filter_outlined,
                size: 64,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              Text(
                _currentQuery.isNotEmpty
                    ? 'Nessun titolo trovato per "$_currentQuery"'
                    : 'Nessun contenuto disponibile al momento',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Prova a cercare con un altro titolo o verifica la connessione.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return _buildVideoGrid();
  }

  /// Genera una griglia responsive con rapporto d'aspetto verticale ottimizzato per le locandine (stile Netflix).
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: GridView responsive per dispositivi mobile, tablet e desktop.
  Widget _buildVideoGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 160).floor().clamp(2, 6);

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          itemCount: _videos.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.65,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final video = _videos[index];
            return _buildVideoCard(video);
          },
        );
      },
    );
  }

  /// Costruisce la singola scheda poster con immagine di copertina, badge del tipo e sovrapposizione gradiente.
  /// Riceve:
  ///   - `video` (VideoModel): Istanza del film o serie TV da renderizzare.
  /// Ritorna:
  ///   - `Widget`: Scheda cliccabile con effetto hover/tap che apre VideoPlayerScreen.
  Widget _buildVideoCard(VideoModel video) {
    final isSeries = video is TvShowModel || video.getType() == 'serie';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoScreen(video: video),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1B),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            const BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.5),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCardImage(video, isSeries),
            Positioned(
              top: 8,
              left: 8,
              child: _buildBadge(isSeries),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(10.0),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color.fromRGBO(0, 0, 0, 0.7),
                      Color.fromRGBO(0, 0, 0, 0.95),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isSeries
                          ? (video is TvShowModel && video.sesson.isNotEmpty
                              ? '${video.sesson.length} ${video.sesson.length == 1 ? 'Stagione' : 'Stagioni'}'
                              : 'Serie TV')
                          : 'Film',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Carica l'immagine di copertina del titolo o mostra il fallback grafico se l'URL non è presente o non risponde.
  /// Riceve:
  ///   - `video` (VideoModel): Istanza del contenuto video.
  ///   - `isSeries` (bool): Flag indicante se il contenuto è una serie TV.
  /// Ritorna:
  ///   - `Widget`: Immagine o fallback stilizzato.
  Widget _buildCardImage(VideoModel video, bool isSeries) {
    if (video.url_image.isEmpty) {
      return _buildFallbackImage(video, isSeries);
    }

    return Image.network(
      video.url_image,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFF1B1B1B),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white24,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildFallbackImage(video, isSeries);
      },
    );
  }

  /// Fornisce un layout grafico con gradiente e icona tematica in caso di locandina assente.
  /// Riceve:
  ///   - `video` (VideoModel): Istanza del contenuto multimediale.
  ///   - `isSeries` (bool): Flag che indica la tipologia serie o film.
  /// Ritorna:
  ///   - `Widget`: Sfondo decorativo con icona e titolo.
  Widget _buildFallbackImage(VideoModel video, bool isSeries) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[900]!,
            Colors.grey[850]!,
            Colors.black,
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSeries ? Icons.tv : Icons.movie,
              color: Colors.red[700],
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              video.name,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Genera un piccolo badge colorato per distinguere a colpo d'occhio film e serie TV sul poster.
  /// Riceve:
  ///   - `isSeries` (bool): Se true colora il badge per Serie TV, altrimenti per Film.
  /// Ritorna:
  ///   - `Widget`: Chip con testo in maiuscolo e colore identificativo.
  Widget _buildBadge(bool isSeries) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isSeries
            ? const Color.fromRGBO(229, 9, 20, 0.9)
            : const Color.fromRGBO(0, 0, 0, 0.75),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSeries ? Colors.transparent : Colors.white24,
          width: 0.5,
        ),
      ),
      child: Text(
        isSeries ? 'SERIE' : 'FILM',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
