// ignore_for_file: public_member_api_docs, sort_constructors_first
class VideoModel {
  String name;
  String description;
  String tmdb_id;
  String url_image;
  VideoModel({
    required this.name,
    required this.description,
    required this.tmdb_id,
    required this.url_image
  });


  String getType(){
    return "null";
  }
}
