class MovieModel {
  final int id;
  final String title;
  final String originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final int? runtime;
  final String? imdbId;

  const MovieModel({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage = 0.0,
    this.runtime,
    this.imdbId,
  });

  factory MovieModel.fromJson(Map<String, dynamic> json) => MovieModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        originalTitle: json['original_title'] as String? ?? '',
        overview: json['overview'] as String?,
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        releaseDate: json['release_date'] as String?,
        voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
        runtime: (json['runtime'] as num?)?.toInt(),
        imdbId: json['imdb_id'] as String?,
      );
}
