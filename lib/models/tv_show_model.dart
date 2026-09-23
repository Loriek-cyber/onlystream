import 'dart:ffi';

import 'package:onlystream/models/video_model.dart';

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

class CurrentEpisode {
  String name;
  String description;
  int season;
  int number;
  TvShowModel tv_show;

  CurrentEpisode({
    required this.name,
    required this.description,
    required this.season,
    required this.number,
    required this.tv_show,
  });
}
