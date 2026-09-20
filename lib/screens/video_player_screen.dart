import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:onlystream/models/video_model.dart' as model;

class VideoPlayerScreen extends StatefulWidget {
  final model.Video video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late model.Video currentVideo;

  late final player = Player();
  late final controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: false, // Fix stuttering on some Linux drivers
    ),
  );

  @override
  void initState() {
    super.initState();
    currentVideo = widget.video;
    _initializePlayer();
  }

  void _initializePlayer() {
    // Prendi l'URL dello stream (italiano di default)
    String streamUrl = currentVideo.getStreamUrl("it");
    debugPrint("🎥 Tentativo di riproduzione stream: $streamUrl");

    // Ascolto degli eventi per capire perché non parte
    player.stream.error.listen((error) {
      debugPrint("❌ ERRORE PLAYER: $error");
    });

    player.stream.playing.listen((playing) {
      debugPrint("▶️ PLAYER RIPRODUZIONE: $playing");
    });

    player.stream.buffering.listen((buffering) {
      debugPrint("⏳ PLAYER IN BUFFERING: $buffering");
    });

    player.stream.log.listen((event) {
      debugPrint("📝 LOG MEDIAKIT: ${event.text}");
    });

    if (player.platform is NativePlayer) {
      // Forza mpv a leggere i flussi con il demuxer mp4 bypassando il probing basato sull'estensione URL
      (player.platform as NativePlayer).setProperty(
        'demuxer-lavf-format',
        'mp4',
      );
    }

    // open() avvia automaticamente il video con play: true
    player
        .open(Media(streamUrl), play: true)
        .then((_) {
          debugPrint("✅ Apertura stream completata con successo");
        })
        .catchError((error) {
          debugPrint("🚨 ERRORE APERTURA STREAM: $error");
        });
  }

  void playNextEpisode() {
    // Per ora, solo un placeholder
    debugPrint("Prossimo episodio: ${currentVideo.nextEpisode?.title}");
  }

  @override
  void dispose() {
    player.dispose();
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
                child: Stack(
                  children: [
                    Video(
                      controller: controller,
                      // Rimuove i controlli predefiniti per permetterti di crearne di tuoi!
                      controls: NoVideoControls,
                    ),
                    // Esempio di controlli custom sovrapposti
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () => player.play(),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.pause,
                                color: Colors.white,
                              ),
                              onPressed: () => player.pause(),
                            ),
                            const Expanded(child: SizedBox()),
                            // Qui potresti aggiungere uno slider per il tempo!
                            const Text(
                              "00:00 / 00:00",
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
