import 'package:flutter/material.dart';
import 'package:onlystream/models/video/tv_show_model.dart';
import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/services/api/api.dart';

class VideoScreen extends StatefulWidget {
  final VideoModel video;

  const VideoScreen({
    super.key,
    required this.video,
  });

  /// Crea lo stato associato alla schermata di dettaglio del video.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `State<VideoScreen>`: Nuova istanza dello stato _VideoScreenState.
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late VideoModel _video;
  List<Sesson> _seasons = [];
  int _selectedSeasonIndex = 0;
  bool _isLoadingSeasons = false;
  bool _isFavorite = false;
  bool _isLoadingFavorite = false;
  Map<String, dynamic>? _movieStreamInfo;

  /// Inizializza lo stato del widget impostando il video e avviando il recupero dei dati asincroni.
  /// Riceve: Nessun parametro.
  /// Ritorna: void.
  @override
  void initState() {
    super.initState();
    _video = widget.video;
    _initData();
  }

  /// Coordina il caricamento dello stato dei preferiti, delle stagioni (per le serie) o delle info tecniche (per i film).
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _initData() async {
    _checkFavoriteStatus();
    final isSeries = _video is TvShowModel || _video.getType() == 'serie';

    if (isSeries) {
      if (_video is TvShowModel && (_video as TvShowModel).sesson.isNotEmpty) {
        final existingSeasons = (_video as TvShowModel).sesson;
        int defaultIndex = 0;
        for (int i = 0; i < existingSeasons.length; i++) {
          if (existingSeasons[i].number == 1) {
            defaultIndex = i;
            break;
          }
        }
        setState(() {
          _seasons = existingSeasons;
          _selectedSeasonIndex = defaultIndex;
        });
      } else {
        await _fetchSeasons();
      }
    } else {
      await _fetchMovieStreamInfo();
    }

    if (_video.description.isEmpty) {
      final results = await SearchApi.search(_video.name);
      if (results.isNotEmpty && mounted) {
        final match = results.firstWhere(
          (r) => r.tmdb_id == _video.tmdb_id,
          orElse: () => results.first,
        );
        if (match.description.isNotEmpty) {
          setState(() {
            _video.description = match.description;
            if (_video.url_image.isEmpty || _video.url_image.contains('w220')) {
              _video.url_image = match.url_image;
            }
          });
        }
      }
    }
  }

  /// Recupera la lista completa di stagioni ed episodi della serie TV tramite DiscoveryApi.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _fetchSeasons() async {
    setState(() => _isLoadingSeasons = true);
    final fetched = await DiscoveryApi.getTvSeasons(_video.tmdb_id);
    if (!mounted) return;

    if (_video is TvShowModel) {
      (_video as TvShowModel).sesson = fetched;
    }

    int defaultIndex = 0;
    for (int i = 0; i < fetched.length; i++) {
      if (fetched[i].number == 1) {
        defaultIndex = i;
        break;
      }
    }

    setState(() {
      _seasons = fetched;
      _selectedSeasonIndex = defaultIndex;
      _isLoadingSeasons = false;
    });
  }

  /// Recupera i dettagli tecnici dello stream del film (lingue audio e qualità video) tramite MovieApi.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _fetchMovieStreamInfo() async {
    final info = await MovieApi.getStreamInfo(_video.tmdb_id);
    if (!mounted) return;

    setState(() {
      _movieStreamInfo = info;
    });
  }

  /// Verifica se il contenuto corrente è presente nella watchlist dei preferiti del server.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _checkFavoriteStatus() async {
    final isSeries = _video is TvShowModel || _video.getType() == 'serie';
    final mediaType = isSeries ? 'tv' : 'movie';
    final isFav = await FavoritesApi.checkFavorite(mediaType, _video.tmdb_id);
    if (!mounted) return;

    setState(() {
      _isFavorite = isFav;
    });
  }

  /// Alterna l'aggiunta o la rimozione del video dai preferiti memorizzati su disco.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Future<void>`: Operazione asincrona completata.
  Future<void> _toggleFavorite() async {
    if (_isLoadingFavorite) return;
    setState(() => _isLoadingFavorite = true);

    final isSeries = _video is TvShowModel || _video.getType() == 'serie';
    final mediaType = isSeries ? 'tv' : 'movie';

    if (_isFavorite) {
      final success = await FavoritesApi.deleteFavorite(mediaType, _video.tmdb_id);
      if (mounted && success) {
        setState(() => _isFavorite = false);
      }
    } else {
      final favoritePayload = {
        'id': int.tryParse(_video.tmdb_id) ?? 0,
        'media_type': mediaType,
        'title': _video.name,
        'poster_url': _video.url_image,
        'overview': _video.description,
      };
      final created = await FavoritesApi.addFavorite(favoritePayload);
      if (mounted && created != null) {
        setState(() => _isFavorite = true);
      }
    }

    if (mounted) {
      setState(() => _isLoadingFavorite = false);
    }
  }

  /// Avvia la riproduzione del contenuto principale o della stagione/episodio correntemente selezionati.
  /// Riceve: Nessun parametro.
  /// Ritorna: void.
  void _playFromHero() {
    final isSeries = _video is TvShowModel || _video.getType() == 'serie';
    if (isSeries && _seasons.isNotEmpty) {
      final currentSeason = _selectedSeasonIndex < _seasons.length
          ? _seasons[_selectedSeasonIndex]
          : _seasons.first;
      final playEpisode = currentSeason.list_episode.isNotEmpty
          ? currentSeason.list_episode.first.number
          : 1;
      _playVideo(season: currentSeason.number, episode: playEpisode);
    } else {
      _playVideo(season: 1, episode: 1);
    }
  }

  /// Avvia la riproduzione del video aprendo VideoPlayerScreen con la stagione e l'episodio specificati.
  /// Riceve:
  ///   - `season` (int, default 1): Numero della stagione da riprodurre.
  ///   - `episode` (int, default 1): Numero dell'episodio da riprodurre.
  /// Ritorna: void.
  void _playVideo({int season = 1, int episode = 1}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          video: _video,
          initialSeason: season,
          initialEpisode: episode,
        ),
      ),
    );
  }

  /// Costruisce l'interfaccia principale con struttura CustomScrollView a scorrimento elegante.
  /// Riceve:
  ///   - `context` (BuildContext): Contesto dell'albero dei widget.
  /// Ritorna:
  ///   - `Widget`: Struttura visuale Scaffold con copertina espandibile e dettagli.
  @override
  Widget build(BuildContext context) {
    final isSeries = _video is TvShowModel || _video.getType() == 'serie';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(isSeries),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderInfo(isSeries),
                  const SizedBox(height: 16),
                  _buildActionButtons(isSeries),
                  const SizedBox(height: 20),
                  _buildOverviewSection(),
                  if (!isSeries && _movieStreamInfo != null) ...[
                    const SizedBox(height: 20),
                    _buildMovieTechnicalInfo(),
                  ],
                  if (isSeries) ...[
                    const SizedBox(height: 24),
                    _buildSeriesEpisodesSection(),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Crea la barra dell'applicazione collassabile (SliverAppBar) con l'immagine di copertina in evidenza.
  /// Riceve:
  ///   - `isSeries` (bool): Flag che indica se il contenuto è una serie TV.
  /// Ritorna:
  ///   - `Widget`: SliverAppBar con effetto dissolvenza sul fondo.
  Widget _buildSliverAppBar(bool isSeries) {
    return SliverAppBar(
      expandedHeight: 340.0,
      pinned: true,
      backgroundColor: const Color(0xFF0F0F0F),
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: const Color.fromRGBO(0, 0, 0, 0.65),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (_video.url_image.isNotEmpty)
              Image.network(
                _video.url_image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[900],
                  child: Icon(
                    isSeries ? Icons.tv : Icons.movie,
                    size: 80,
                    color: Colors.white24,
                  ),
                ),
              )
            else
              Container(
                color: Colors.grey[900],
                child: Icon(
                  isSeries ? Icons.tv : Icons.movie,
                  size: 80,
                  color: Colors.white24,
                ),
              ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(0, 0, 0, 0.5),
                    Colors.transparent,
                    Color.fromRGBO(15, 15, 15, 0.8),
                    Color(0xFF0F0F0F),
                  ],
                  stops: [0.0, 0.4, 0.8, 1.0],
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: _playFromHero,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color.fromRGBO(229, 9, 20, 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.6),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Crea la sezione del titolo, badge e metadati descrittivi.
  /// Riceve:
  ///   - `isSeries` (bool): Flag che distingue le serie TV dai film.
  /// Ritorna:
  ///   - `Widget`: Titolo con badge di tipologia e conteggio stagioni.
  Widget _buildHeaderInfo(bool isSeries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _video.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSeries
                    ? const Color(0xFFE50914)
                    : Colors.white12,
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
            const SizedBox(width: 10),
            Text(
              'TMDB ID: ${_video.tmdb_id}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            if (isSeries && _seasons.isNotEmpty) ...[
              const SizedBox(width: 10),
              const Text('•', style: TextStyle(color: Colors.white38)),
              const SizedBox(width: 10),
              Text(
                '${_seasons.length} ${_seasons.length == 1 ? 'Stagione' : 'Stagioni'}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Costruisce i pulsanti principali di azione (Riproduci e Aggiungi/Rimuovi Preferito).
  /// Riceve:
  ///   - `isSeries` (bool): Flag tipologia contenuto.
  /// Ritorna:
  ///   - `Widget`: Riga con pulsante di riproduzione primario e pulsante preferiti.
  Widget _buildActionButtons(bool isSeries) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: _playFromHero,
            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 26),
            label: const Text(
              'Riproduci',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 4,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: _isLoadingFavorite ? null : _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.bookmark : Icons.bookmark_border,
              color: _isFavorite ? Colors.amber : Colors.white70,
              size: 22,
            ),
            label: Text(
              _isFavorite ? 'Salvato' : 'Preferito',
              style: TextStyle(
                color: _isFavorite ? Colors.amber : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: _isFavorite ? Colors.amber : Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Costruisce il paragrafo con la trama e descrizione della scheda.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Blocco con titolo "Trama" e testo descrittivo.
  Widget _buildOverviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trama',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _video.description.isNotEmpty
              ? _video.description
              : 'Nessuna descrizione o trama disponibile per questo titolo.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.5,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  /// Costruisce una scheda informativa con le tracce audio e le qualità rilevate per il film.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Riquadro con informazioni tecniche sullo streaming.
  Widget _buildMovieTechnicalInfo() {
    final audioList = _movieStreamInfo?['audio'] as List<dynamic>? ?? [];
    final qualityList = _movieStreamInfo?['qualities'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'Dettagli Streaming',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (audioList.isNotEmpty) ...[
            Text(
              'Lingue Audio: ${audioList.map((a) => a['name'] ?? a['language']).join(', ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
          ],
          if (qualityList.isNotEmpty)
            Text(
              'Risoluzioni: ${qualityList.map((q) => q['resolution']).where((r) => r != null).join(', ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
    );
  }

  /// Costruisce la sezione completa dedicata agli episodi per le serie TV.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Selettore della stagione e lista degli episodi corrispondenti.
  Widget _buildSeriesEpisodesSection() {
    if (_isLoadingSeasons) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(color: Colors.red),
        ),
      );
    }

    if (_seasons.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          'Nessun episodio caricato per questa serie TV.',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    final currentSeason = _selectedSeasonIndex < _seasons.length
        ? _seasons[_selectedSeasonIndex]
        : _seasons.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSeasonSelector(),
        const SizedBox(height: 12),
        _buildEpisodesList(currentSeason),
      ],
    );
  }

  /// Crea il selettore delle stagioni tramite pulsanti orizzontali a scorrimento (chips).
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `Widget`: Barra di selezione a scorrimento con le etichette delle stagioni.
  Widget _buildSeasonSelector() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _seasons.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final season = _seasons[index];
          final isSelected = index == _selectedSeasonIndex;

          return ChoiceChip(
            label: Text(
              season.name.isNotEmpty
                  ? season.name
                  : (season.number == 0 ? 'Speciali' : 'Stagione ${season.number}'),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            selected: isSelected,
            selectedColor: const Color(0xFFE50914),
            backgroundColor: const Color(0xFF1F1F1F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isSelected ? Colors.transparent : Colors.white12,
              ),
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedSeasonIndex = index);
              }
            },
          );
        },
      ),
    );
  }

  /// Costruisce la lista verticale degli episodi appartenenti alla stagione selezionata.
  /// Riceve:
  ///   - `currentSeason` (Sesson): Oggetto stagione contenente la lista degli episodi.
  /// Ritorna:
  ///   - `Widget`: Colonna di elementi scheda per ogni episodio.
  Widget _buildEpisodesList(Sesson currentSeason) {
    if (currentSeason.list_episode.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          'Nessun episodio disponibile in questa stagione.',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: currentSeason.list_episode.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final episode = currentSeason.list_episode[index];
        return _buildEpisodeTile(currentSeason, episode);
      },
    );
  }

  /// Costruisce la singola riga cliccabile che visualizza l'episodio con numero, titolo e icona play.
  /// Riceve:
  ///   - `season` (Sesson): Stagione di appartenenza dell'episodio.
  ///   - `episode` (Episode): Istanza dell'episodio.
  /// Ritorna:
  ///   - `Widget`: Card interattiva in stile Netflix.
  Widget _buildEpisodeTile(Sesson season, Episode episode) {
    return Material(
      color: const Color(0xFF191919),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _playVideo(
          season: season.number,
          episode: episode.number,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${episode.number}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title.isNotEmpty
                          ? episode.title
                          : 'Episodio ${episode.number}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (episode.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.description,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.play_circle_fill,
                color: Color(0xFFE50914),
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
