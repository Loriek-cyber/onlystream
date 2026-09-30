import 'package:onlystream/models/video/video_model.dart';

class Episode {
  String title;
  String description;
  int number;
  String image_url;

  /// Costruttore per creare un episodio di una serie TV.
  /// Riceve:
  ///   - `title` (String): Titolo dell'episodio.
  ///   - `description` (String): Descrizione o sinossi dell'episodio.
  ///   - `number` (int): Numero progressivo dell'episodio nella stagione.
  ///   - `image_url` (String): URL dell'immagine di anteprima.
  /// Ritorna:
  ///   - `Episode`: Nuova istanza di Episode.
  Episode(this.title, this.description, this.number, this.image_url);
}

class Sesson {
  int number;
  List<Episode> list_episode;
  String name;

  /// Costruttore per rappresentare una stagione di una serie TV.
  /// Riceve:
  ///   - `number` (int): Numero identificativo della stagione (es. 1 per Stagione 1, 0 per Speciali).
  ///   - `list_episode` (`List<Episode>`): Elenco degli episodi appartenenti a questa stagione.
  ///   - `name` (String, opzionale, default ''): Denominazione della stagione (es. 'Stagione 1', 'Speciali').
  /// Ritorna:
  ///   - `Sesson`: Nuova istanza di Sesson.
  Sesson(this.number, this.list_episode, [this.name = '']);
}

class TvShowModel extends VideoModel {
  List<Sesson> sesson;

  /// Costruttore per il modello di dati di una serie televisiva polimorfica.
  /// Riceve:
  ///   - `name` (String): Titolo della serie TV.
  ///   - `description` (String): Descrizione o sinossi generale della serie.
  ///   - `tmdb_id` (String): ID numerico identificativo su The Movie Database.
  ///   - `url_image` (String): URL della locandina o del poster.
  ///   - `sesson` (`List<Sesson>`): Lista delle stagioni disponibili.
  /// Ritorna:
  ///   - `TvShowModel`: Nuova istanza di TvShowModel.
  TvShowModel({
    required super.name,
    required super.description,
    required super.tmdb_id,
    required super.url_image,
    required this.sesson,
  });

  /// Restituisce la tipologia di contenuto multimediale associata al modello.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `String`: La stringa costante "serie".
  @override
  String getType() {
    return "serie";
  }

  /// Restituisce il numero totale di stagioni presenti nel modello.
  /// Riceve: Nessun parametro.
  /// Ritorna:
  ///   - `int`: Conteggio delle stagioni memorizzate.
  int lenSesson() {
    return sesson.length;
  }
}

