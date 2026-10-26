import 'package:flutter/material.dart';
import 'package:onlystream/services/server_config_service.dart';

/// Quick Dialog to view/change the main EasyStream API server IP/URL,
/// test `/health` connectivity, or pick from saved presets.
class ServerQuickDialog extends StatefulWidget {
  const ServerQuickDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ServerQuickDialog(),
    );
  }

  @override
  State<ServerQuickDialog> createState() => _ServerQuickDialogState();
}

class _ServerQuickDialogState extends State<ServerQuickDialog> {
  final _config = ServerConfigService.instance;
  late TextEditingController _urlController;
  final TextEditingController _nameController = TextEditingController();
  bool _isTesting = false;
  ServerStatus? _testResult;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _config.baseUrl);
    _testResult = _config.status;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;
    setState(() => _isTesting = true);
    final res = await _config.setServerUrl(
      raw,
      presetName: _nameController.text.trim(),
    );
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = res;
        _urlController.text = _config.baseUrl;
        _nameController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF121722),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF232B3E)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.dns_rounded,
              color: Color(0xFF06B6D4),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Configura IP Server Principale',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live Status Banner
              if (_testResult != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: (_testResult!.isOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF43F5E))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _testResult!.isOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF43F5E),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testResult!.isOnline
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        color: _testResult!.isOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF43F5E),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _testResult!.isOnline
                              ? 'Connesso a ${_testResult!.serviceName} v${_testResult!.version} (${_testResult!.latencyMs} ms)'
                              : 'Server non raggiungibile su ${_config.baseUrl}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const Text(
                'Indirizzo IP o URL del Server EasyStream API:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'es. 192.168.1.50:5555 o http://localhost:5555',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0A0D14),
                  prefixIcon:
                      const Icon(Icons.link_rounded, color: Color(0xFF38BDF8)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF232B3E)),
                  ),
                ),
                onSubmitted: (_) => _testAndSave(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nome preset opzionale (es. Server Casa)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0A0D14),
                  prefixIcon: const Icon(
                    Icons.bookmark_border_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF232B3E)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Server Salvati (clicca per cambiare rapidamente):',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ..._config.presets.map((preset) {
                final isCurrent = preset.url == _config.baseUrl;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? const Color(0xFF06B6D4).withValues(alpha: 0.15)
                        : const Color(0xFF0A0D14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent
                          ? const Color(0xFF06B6D4)
                          : const Color(0xFF232B3E),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () {
                      _urlController.text = preset.url;
                      _testAndSave();
                    },
                    title: Text(
                      preset.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      preset.url,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 11.5,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF06B6D4),
                            size: 18,
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                            onPressed: () async {
                              await _config.removePreset(preset.url);
                              if (mounted) setState(() {});
                            },
                          ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF06B6D4),
            foregroundColor: Colors.white,
          ),
          onPressed: _isTesting ? null : _testAndSave,
          icon: _isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: Text(_isTesting ? 'Verifica...' : 'Applica & Verifica'),
        ),
      ],
    );
  }
}
