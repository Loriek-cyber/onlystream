import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystream/screens/app_shell.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ConfigService.instance.init();
  await LibraryService.instance.init();
  runApp(const OnlyStreamApp());
}

class OnlyStreamApp extends StatelessWidget {
  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;
  final bool loadHomeOnInit;

  const OnlyStreamApp({
    super.key,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
    this.loadHomeOnInit = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnlyStream',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: AppShell(
        apiClient: apiClient,
        configService: configService,
        libraryService: libraryService,
        torrentGuard: torrentGuard,
        playerFactory: playerFactory,
        loadHomeOnInit: loadHomeOnInit,
      ),
    );
  }
}
