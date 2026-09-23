import 'dart:ffi';

class TvShowModel {
  Long id;
  String name;
  String description;
  String tmdb_id;

  TvShowModel({
    required this.id,
    required this.name,
    required this.description,
    required this.tmdb_id,
  });
}
