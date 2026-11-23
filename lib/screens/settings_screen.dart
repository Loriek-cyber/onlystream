import 'package:flutter/material.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final ConfigService? configService;

  const SettingsScreen({super.key, this.configService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ConfigService _config;
  late final TextEditingController _urlController;
  bool _companionBusy = false;
  String? _feedbackMessage;

  @override
  void initState() {
    super.initState();
    _config = widget.configService ?? ConfigService.instance;
    _urlController = TextEditingController(text: _config.remoteUrl);
    _config.addListener(_onConfigChanged);
    _config.refreshCompanionStatus();
  }

  void _onConfigChanged() {
    if (!mounted) return;
    if (_urlController.text != _config.remoteUrl &&
        !FocusScope.of(context).hasFocus) {
      _urlController.text = _config.remoteUrl;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveRemoteUrl() async {
    FocusScope.of(context).unfocus();
    final status = await _config.setRemoteUrl(_urlController.text);
    if (!mounted) return;
    setState(() {
      _feedbackMessage = status.isOnline
          ? 'Connesso (${status.latencyMs} ms)'
          : 'Connessione non riuscita: ${status.error ?? "Server non raggiungibile"}';
    });
  }

  Future<void> _checkHealth() async {
    final status = await _config.checkHealth();
    if (!mounted) return;
    setState(() {
      _feedbackMessage = status.isOnline
          ? 'Server attivo · v${status.version} (${status.latencyMs} ms)'
          : 'Server non raggiungibile${status.error != null ? " · ${status.error}" : ""}';
    });
  }

  Future<void> _startCompanion() async {
    setState(() => _companionBusy = true);
    final ok = await _config.startLocalServer();
    if (!mounted) return;
    setState(() {
      _companionBusy = false;
      _feedbackMessage = ok
          ? 'Richiesta avvio server inviata'
          : 'Impossibile avviare il server locale';
    });
  }

  Future<void> _stopCompanion() async {
    setState(() => _companionBusy = true);
    final ok = await _config.stopLocalServer();
    if (!mounted) return;
    setState(() {
      _companionBusy = false;
      _feedbackMessage = ok
          ? 'Richiesta arresto server inviata'
          : 'Impossibile arrestare il server locale';
    });
  }

  Future<void> _showAddPresetDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController(text: _urlController.text);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuovo preset server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Casa LAN',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Indirizzo URL',
                hintText: 'http://192.168.1.100:5555',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (confirmed == true && urlController.text.trim().isNotEmpty) {
      await _config.addPreset(nameController.text, urlController.text);
    }
    nameController.dispose();
    urlController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _config.status;

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              const _SectionHeader(title: 'Server'),
              const SizedBox(height: 10),
              _SettingsGroupCard(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _config.isChecking
                              ? AppColors.textSecondary
                              : (status.isOnline
                                  ? AppColors.online
                                  : AppColors.accent),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.isOnline
                                  ? 'Server connesso'
                                  : 'Server non raggiungibile',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_config.baseUrl}${status.isOnline && status.version.isNotEmpty ? " · v${status.version} · ${status.latencyMs} ms" : ""}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _config.isChecking ? null : _checkHealth,
                        child: Text(
                          _config.isChecking ? 'Verifica...' : 'Verifica',
                        ),
                      ),
                    ],
                  ),
                  if (_feedbackMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _feedbackMessage!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const Divider(height: 28),
                  const Text(
                    'Modalità connessione',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'local',
                          label: Text('Locale (Android)'),
                        ),
                        ButtonSegment(
                          value: 'remote',
                          label: Text('Remoto'),
                        ),
                      ],
                      selected: {_config.serverMode},
                      onSelectionChanged: (selection) {
                        _config.setServerMode(selection.first);
                      },
                    ),
                  ),
                  if (_config.serverMode == 'local') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Server locale Android (127.0.0.1:5555)',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                _config.companionInstalled
                                    ? 'Installato'
                                    : (_config.isAndroid
                                        ? 'Non installato'
                                        : 'Solo Android'),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: (_companionBusy ||
                                        !_config.companionInstalled)
                                    ? null
                                    : _startCompanion,
                                child: const Text('Avvia server'),
                              ),
                              OutlinedButton(
                                onPressed: (_companionBusy ||
                                        !_config.companionInstalled)
                                    ? null
                                    : _stopCompanion,
                                child: const Text('Ferma server'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_config.serverMode == 'remote') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Indirizzo server',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              hintText: 'http://192.168.1.100:5555',
                            ),
                            onSubmitted: (_) => _saveRemoteUrl(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _saveRemoteUrl,
                          child: const Text('Salva'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Preset salvati',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showAddPresetDialog,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Aggiungi'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ..._config.presets.map((preset) {
                      final active = _config.remoteUrl == preset.url;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          preset.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          preset.url,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        leading: Icon(
                          active
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: active
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          tooltip: 'Rimuovi preset',
                          onPressed: () => _config.removePreset(preset.url),
                        ),
                        onTap: () {
                          _urlController.text = preset.url;
                          _config.setRemoteUrl(preset.url);
                        },
                      );
                    }),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              const _SectionHeader(title: 'Riproduzione'),
              const SizedBox(height: 10),
              _SettingsGroupCard(
                children: [
                  const Text(
                    'Lingua predefinita',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: const [
                      ('it', 'Italiano'),
                      ('en', 'English'),
                    ].map((opt) {
                      final selected = _config.language == opt.$1;
                      return ChoiceChip(
                        label: Text(opt.$2),
                        selected: selected,
                        onSelected: (_) =>
                            _config.setPreferences(language: opt.$1),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Qualità video preferita',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      ('auto', 'Auto'),
                      ('2160p', '2160p'),
                      ('1080p', '1080p'),
                      ('720p', '720p'),
                    ].map((opt) {
                      final selected = _config.quality == opt.$1;
                      return ChoiceChip(
                        label: Text(opt.$2),
                        selected: selected,
                        onSelected: (_) =>
                            _config.setPreferences(quality: opt.$1),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Sorgente preferita',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: const [
                      ('auto', 'Auto'),
                      ('hls', 'HLS'),
                      ('torrent', 'Torrent'),
                    ].map((opt) {
                      final selected = _config.source == opt.$1;
                      return ChoiceChip(
                        label: Text(opt.$2),
                        selected: selected,
                        onSelected: (_) =>
                            _config.setPreferences(source: opt.$1),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
