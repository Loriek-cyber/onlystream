import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystream/screens/home_screen.dart';
import 'package:onlystream/services/download_service.dart';
import 'package:onlystream/services/server_config_service.dart';

/*
Be careful to not use Future<void> becouse it breaks the stream
*/
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ServerConfigService.instance.init();
  await DownloadService.instance.init();
  runApp(const MyApp());
}

// [Main_Application]
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF06B6D4),
          brightness: Brightness.dark,
          primary: const Color(0xFF06B6D4),
          secondary: const Color(0xFF3B82F6),
          surface: const Color(0xFF121722),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0D14),
      ),
      home: const HomeScreen(),
    );
  }
}
