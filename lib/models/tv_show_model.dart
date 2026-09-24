import 'package:onlystream/models/show_model.dart';

class TvShowModel extends ShowModel {
  new({
    required super.name,
    required super.description,
    required super.tmdb_id,
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
