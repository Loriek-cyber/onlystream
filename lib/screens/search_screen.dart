import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/screens/media_detail_screen.dart';
import 'package:onlystream/services/api_client.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/services/library_service.dart';
import 'package:onlystream/services/player_adapter.dart';
import 'package:onlystream/services/torrent_session_guard.dart';
import 'package:onlystream/theme/app_theme.dart';
import 'package:onlystream/widgets/media_cards.dart';

class SearchScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final ConfigService? configService;
  final LibraryService? libraryService;
  final TorrentSessionGuard? torrentGuard;
  final PlayerAdapter Function()? playerFactory;

  const SearchScreen({
    super.key,
    this.apiClient,
    this.configService,
    this.libraryService,
    this.torrentGuard,
    this.playerFactory,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final ApiClient _apiClient;
  late final ConfigService _config;
  late final LibraryService _library;
  final TextEditingController _controller = TextEditingController();

  Timer? _debounce;
  int _requestEpoch = 0;
  String _selectedType = 'all';
  bool _isSearching = false;
  String? _error;
  List<MediaSummary> _results = const [];

  static const _filters = [
    ('all', 'Tutti'),
    ('movie', 'Film'),
    ('tv', 'Serie'),
    ('anime', 'Anime'),
  ];

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient.instance;
    _config = widget.configService ?? ConfigService.instance;
    _library = widget.libraryService ?? LibraryService.instance;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _requestEpoch++;
        _isSearching = false;
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_executeSearch(trimmed));
    });
  }

  Future<void> _executeSearch(String query) async {
    final epoch = ++_requestEpoch;
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await _apiClient.search(
        query,
        type: _selectedType,
        lang: _config.language,
      );
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || epoch != _requestEpoch) return;
      setState(() {
        _isSearching = false;
        _error = 'Ricerca non riuscita: $e';
      });
    }
  }

  void _selectFilter(String type) {
    if (_selectedType == type) return;
    setState(() => _selectedType = type);
    final trimmed = _controller.text.trim();
    if (trimmed.isNotEmpty) {
      _debounce?.cancel();
      unawaited(_executeSearch(trimmed));
    }
  }

  void _openDetail(MediaSummary item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailScreen(
          summary: item,
          apiClient: _apiClient,
          configService: _config,
          libraryService: _library,
          torrentGuard: widget.torrentGuard,
          playerFactory: widget.playerFactory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                onChanged: _onQueryChanged,
                onSubmitted: (val) {
                  _debounce?.cancel();
                  final trimmed = val.trim();
                  if (trimmed.isNotEmpty) {
                    unawaited(_executeSearch(trimmed));
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Cerca film, serie TV o anime...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textMuted,
                  ),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.$2),
                        selected: _selectedType == f.$1,
                        onSelected: (_) => _selectFilter(f.$1),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildResultsBody(query),
        ),
      ],
    );
  }

  Widget _buildResultsBody(String query) {
    if (query.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Digita un titolo per cercare nel catalogo.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _executeSearch(query),
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'Nessun risultato trovato.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 165,
        mainAxisSpacing: 16,
        crossAxisSpacing: 14,
        childAspectRatio: 0.52,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return PosterMediaCard(
          item: item,
          onTap: () => _openDetail(item),
        );
      },
    );
  }
}
