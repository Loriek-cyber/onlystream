import 'package:flutter/material.dart';
import 'package:onlystream/models/video/tv_show_model.dart';
import 'package:onlystream/models/video/video_model.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/test/test_player.dart';

class FilmSelectorScreen extends StatelessWidget {
  const FilmSelectorScreen({super.key});

  // 1. Lista dei video di test da mostrare
  List<VideoModel> get _testVideos => [
        TestData.breakingBadSeries,
        TestData.oppenheimer,
        TestData.strangerThings,
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleziona un contenuto'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: ListView.builder(
        itemCount: _testVideos.length,
        itemBuilder: (context, index) {
          final video = _testVideos[index];
          final isSeries =
              video is TvShowModel || video.getType() == 'serie';

          return Card(
            color: Colors.grey[900],
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              // Icona in base al tipo (Serie o Film)
              leading: Icon(
                isSeries ? Icons.tv : Icons.movie,
                color: Colors.red,
                size: 32,
              ),
              // Titolo del video
              title: Text(
                video.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Sottotitolo con tipo ed eventuale stagione
              subtitle: Text(
                isSeries
                    ? (video is TvShowModel && video.sesson.isNotEmpty
                        ? 'Serie TV • ${video.sesson.length} ${video.sesson.length == 1 ? 'Stagione' : 'Stagioni'}'
                        : 'Serie TV')
                    : 'Film',
                style: const TextStyle(color: Colors.grey),
              ),
              // Icona Play a destra
              trailing: const Icon(
                Icons.play_circle_fill,
                color: Colors.red,
                size: 32,
              ),
              // Action: Apertura del player video
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(video: video),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}