import 'package:flutter/material.dart';
import 'package:onlystream/screens/home_screen.dart';
import 'package:onlystream/screens/library_screen.dart';
import 'package:onlystream/screens/search_screen.dart';
import 'package:onlystream/screens/settings_screen.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/media_cards.dart';

class AppShell extends StatefulWidget {
  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;
  final bool loadHomeOnInit;
  final int initialIndex;

  const AppShell({
    super.key,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
    this.loadHomeOnInit = true,
    this.initialIndex = 0,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final ApiClient _apiClient;
  late final ConfigService _config;
  late final LibraryService _library;
  late int _selectedIndex;

  static const _titles = ['OnlyStream', 'Cerca', 'Libreria'];

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;
    _selectedIndex = widget.initialIndex.clamp(0, 2);
    _config.addListener(_onConfigChanged);
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(configService: _config),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 840;

    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        HomeScreen(
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
          loadOnInit: widget.loadHomeOnInit,
        ),
        SearchScreen(
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
        ),
        LibraryScreen(
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
        ),
      ],
    );

    final appBar = AppBar(
      title: Text(_titles[_selectedIndex]),
      actions: [
        Center(
          child: ServerStatusPill(
            config: _config,
            onTap: _openSettings,
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Impostazioni',
          onPressed: _openSettings,
        ),
        const SizedBox(width: 8),
      ],
    );

    if (isWide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _selectedIndex = idx),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.search_rounded),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: Text('Cerca'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.video_library_outlined),
                  selectedIcon: Icon(Icons.video_library_rounded),
                  label: Text('Libreria'),
                ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: body,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: NavigationBar(
          height: 66,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'Cerca',
            ),
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              selectedIcon: Icon(Icons.video_library_rounded),
              label: 'Libreria',
            ),
          ],
        ),
      ),
    );
  }
}
