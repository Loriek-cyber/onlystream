import 'package:onlystream/models/video/video_model.dart';

class Episode{
  String title;
  String description;
  int number;
  String image_url;
  Episode(this.title, this.description, this.number, this.image_url);
}

class Sesson{
  int number;
  List<Episode> list_episode;
  Sesson(this.number, this.list_episode);

}


class TvShowModel extends VideoModel {
  //sesson;
  List<Sesson> sesson;
  TvShowModel({
    required super.name,
    required super.description,
    required super.tmdb_id,
    required super.url_image,
    required this.sesson
  });
  @override
  String getType() {
    return "serie";
  }
  int lenSesson(){
    return sesson.length;
  }
}

