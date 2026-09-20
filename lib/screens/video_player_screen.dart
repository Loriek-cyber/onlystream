import 'package:flutter/material.dart';
import 'package:better_player/better_player.dart';
import 'package:onlystream/models/video_model.dart' as model;

class VideoPlayerScreen extends StatefulWidget {
  final model.Video video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late model.Video currentVideo;
  late BetterPlayerController _betterPlayerController;

  @override
  void initState() {
    super.initState();
    currentVideo = widget.video;
    _initializePlayer();
  }

  void _initializePlayer() {
    String streamUrl = currentVideo.getStreamUrl("it");

    PlayerDataSource betterPlayerDataSource = PlayerDataSource(
      DataSourceType.network,
      streamUrl,
    );

    _betterPlayerController = BetterPlayerController(
      const PlayerConfiguration(
        aspectRatio: 16 / 9,
        autoPlay: true,
        fit: BoxFit.contain,
      ),
      betterPlayerDataSource: betterPlayerDataSource,
    );
  }

  void playNextEpisode() {
    // Per ora, solo un placeholder
    debugPrint("Prossimo episodio: ${currentVideo.nextEpisode?.title}");
  }

  @override
  void dispose() {
    _betterPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Player
              AspectRatio(
                aspectRatio: 16 / 9,
                child: BetterPlayer(
                  controller: _betterPlayerController,
                ),
              ),
              // Info video
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentVideo.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (currentVideo.type == "series" &&
                        currentVideo.currentEpisode != null)
                      Text(
                        "S${currentVideo.currentEpisode!.season}E${currentVideo.currentEpisode!.number} - ${currentVideo.currentEpisode!.title}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              // Pulsante prossimo episodio
              if (currentVideo.type == "series" &&
                  currentVideo.nextEpisode != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: playNextEpisode,
                    child: Text(
                      "Prossimo: S${currentVideo.nextEpisode!.season}E${currentVideo.nextEpisode!.number}",
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
