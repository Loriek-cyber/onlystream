import 'package:onlystream/models/video/movie_model.dart';
import 'package:onlystream/models/video/tv_show_model.dart';

// [Test_Data]
class TestData {
  // TV Series: Breaking Bad
  static final TvShowModel breakingBadSeries = TvShowModel(
    name: 'Breaking Bad',
    description:
        'Un professore di chimica con diagnosi di cancro terminale inizia a produrre metanfetamina per assicurare il futuro della sua famiglia.',
    tmdb_id: '1396',
    url_image:
        'https://image.tmdb.org/t/p/w500/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg',
    sesson: [
      Sesson(1, [
        Episode(
          'Pilot',
          'Un professore di chimica delle superiori con cancro terminale...',
          1,
          'https://image.tmdb.org/t/p/w500/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg',
        ),
        Episode(
          'Cat\'s in the Bag...',
          'Walt e Jesse tentano di disfarsi dei due cadaveri...',
          2,
          'https://image.tmdb.org/t/p/w500/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg',
        ),
      ]),
    ],
  );

  // Movie: Oppenheimer
  static final MovieModel oppenheimer = MovieModel(
    name: 'Oppenheimer',
    description:
        'La storia del fisico statunitense J. Robert Oppenheimer e il suo ruolo nello sviluppo della bomba atomica.',
    tmdb_id: '872585',
    url_image:
        'https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
  );

  // TV Series: Stranger Things
  static final TvShowModel strangerThings = TvShowModel(
    name: 'Stranger Things',
    description:
        'Quando un bambino scompare, una piccola cittadina scopre un mistero che coinvolge esperimenti segreti e forze soprannaturali.',
    tmdb_id: '66732',
    url_image:
        'https://image.tmdb.org/t/p/w500/49WJfeN0moxb9IPfGn8AIqMGskD.jpg',
    sesson: [
      Sesson(1, [
        Episode(
          'The Vanishing of Will Byers',
          'Sulla via di casa dopo una partita a D&D, un ragazzino vede qualcosa di terrificante...',
          1,
          'https://image.tmdb.org/t/p/w500/49WJfeN0moxb9IPfGn8AIqMGskD.jpg',
        ),
        Episode(
          'The Weirdo on Maple Street',
          'Mike nasconde la ragazzina a casa sua. Dustin e Lucas provano a capire chi sia...',
          2,
          'https://image.tmdb.org/t/p/w500/49WJfeN0moxb9IPfGn8AIqMGskD.jpg',
        ),
      ]),
    ],
  );
}
