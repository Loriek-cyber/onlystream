import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:onlystream/screens/app_shell.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/desktop_window_controller.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/desktop_window_frame.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ConfigService.instance.init();
  await LibraryService.instance.init();
  await DesktopWindowController.instance.init();
  runApp(const OnlyStreamApp());
}

class OnlyStreamApp extends StatelessWidget {
  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;
  final DesktopWindowController? windowController;
  final bool loadHomeOnInit;

  const OnlyStreamApp({
    super.key,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
    this.windowController,
    this.loadHomeOnInit = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnlyStream',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      scrollBehavior: const AppScrollBehavior(),
      builder: (context, child) => DesktopWindowFrame(
        controller: windowController,
        child: child ?? const SizedBox.shrink(),
      ),
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
