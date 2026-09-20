import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:onlystream/models/video_model.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Video video;

  const VideoPlayerScreen({required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late Video currentVideo;
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;

  @override
  void initState() {
    super.initState();
    currentVideo = widget.video;
    _initializePlayer();
  }

  void _initializePlayer() {
    // Prendi l'URL dello stream (italiano di default)
    String streamUrl = currentVideo.getStreamUrl("it");

    _videoPlayerController = VideoPlayerController.network(streamUrl);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
    );
  }

  void playNextEpisode() {
    // Per ora, solo un placeholder
    print("Prossimo episodio: ${currentVideo.nextEpisode?.title}");
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Player
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Chewie(controller: _chewieController),
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
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
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
    );
  }
}
