import 'package:flutter/material.dart';
import 'package:onlystream/screens/video_player_screen.dart';
import 'package:onlystream/test/test_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnlyStream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: Colors.red,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: VideoPlayerScreen(video: TestData.breakingBadSeries),
      // Prova altri video:
      // home: VideoPlayerScreen(video: TestData.oppenheimer),
      // home: VideoPlayerScreen(video: TestData.strangerThings),
    );
  }
}
