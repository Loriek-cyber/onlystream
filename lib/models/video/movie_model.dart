import 'package:onlystream/models/video/video_model.dart';

class MovieModel extends VideoModel {
  MovieModel({
    required super.name,
    required super.description,
    required super.tmdb_id,
    required super.url_image,
  });

  @override
  String getType() {
    return "movie";
  }


}
