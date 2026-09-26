/*
* This class is a WEAK one with the id of the user and the series id as is main ids
* */

class WhachedModel {
  int id_user;
  String tmdb_id;
  Duration durataVideo;
  int? ep;
  int? sesson;

  WhachedModel(this.id_user,
      this.tmdb_id,
      this.durataVideo,
      this.ep,
      this.sesson);
}