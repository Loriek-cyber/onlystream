import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/test/test_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: VideoPlayerScreen(video: TestData.breakingBadSeries),
    );
  }
}
