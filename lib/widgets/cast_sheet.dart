import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cast/cast_controller.dart';
import '../services/cast/dlna_service.dart';
import '../theme/app_theme.dart';

/// Monochrome dark cinema Cast modal sheet supporting:
/// - Active Cast remote control (play/pause, -10s/+10s, seek bar, volume, disconnect)
/// - Web Receiver (LAN URL, Base36 pairing code, copy actions, connection status)
/// - DLNA / Smart TV discovery & one-tap casting
class CastSheet extends StatefulWidget {
  const CastSheet({
    super.key,
    required this.controller,
    required this.mediaUrl,
    required this.title,
    this.headers,
    this.subtitleUrl,
    this.posterUrl,
    this.initialPosition = Duration.zero,
    this.isHls = false,
    this.onCastStarted,
    this.onDisconnected,
  });

  final CastController controller;
  final String mediaUrl;
  final String title;
  final Map<String, String>? headers;
  final String? subtitleUrl;
  final String? posterUrl;
  final Duration initialPosition;
  final bool isHls;

  /// Invoked when casting starts on either Web Receiver or a DLNA Smart TV.
  final VoidCallback? onCastStarted;

  /// Invoked when the user disconnects from an active Cast session, carrying
  /// the last known playback position on the TV so local playback can resume.
  final ValueChanged<Duration>? onDisconnected;

  /// Opens [CastSheet] as a tall monochrome dark modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required CastController controller,
    required String mediaUrl,
    required String title,
    Map<String, String>? headers,
    String? subtitleUrl,
    String? posterUrl,
    Duration initialPosition = Duration.zero,
    bool isHls = false,
    VoidCallback? onCastStarted,
    ValueChanged<Duration>? onDisconnected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.border, width: 1),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: CastSheet(
          controller: controller,
          mediaUrl: mediaUrl,
          title: title,
          headers: headers,
          subtitleUrl: subtitleUrl,
          posterUrl: posterUrl,
          initialPosition: initialPosition,
          isHls: isHls,
          onCastStarted: onCastStarted,
          onDisconnected: onDisconnected,
        ),
      ),
    );
  }

  @override
  State<CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<CastSheet> {
  double? _draggingSeekSeconds;
  double? _draggingVolume;
  bool _startingCast = false;

  @override
  void initState() {
    super.initState();
    _initCast();
  }

  Future<void> _initCast() async {
    await widget.controller.startServer();
    if (widget.controller.dlnaDevices.isEmpty) {
      await widget.controller.discoverDlna();
    }
  }

  Future<void> _startCast({DlnaDevice? dlnaDevice}) async {
    if (_startingCast) return;
    setState(() => _startingCast = true);
    try {
      await widget.controller.castMedia(
        url: widget.mediaUrl,
        title: widget.title,
        headers: widget.headers,
        subtitleUrl: widget.subtitleUrl,
        posterUrl: widget.posterUrl,
        initialPosition: widget.initialPosition,
        isHls: widget.isHls,
        dlnaDevice: dlnaDevice,
      );
      widget.onCastStarted?.call();
    } finally {
      if (mounted) {
        setState(() => _startingCast = false);
      }
    }
  }

  Future<void> _disconnect() async {
    final lastPosition = widget.controller.position;
    await widget.controller.disconnect();
    widget.onDisconnected?.call(lastPosition);
  }

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiato negli appunti'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        return Material(
          color: AppColors.background,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                  child: Row(
                    children: [
                      Icon(
                        ctrl.isCasting
                            ? Icons.cast_connected_rounded
                            : Icons.cast_rounded,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Trasmetti su TV',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Chiudi',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      if (ctrl.isCasting) ...[
                        _buildRemoteControlCard(ctrl),
                        const SizedBox(height: 16),
                      ],
                      if (ctrl.lastError != null) ...[
                        _buildErrorBanner(ctrl.lastError!),
                        const SizedBox(height: 16),
                      ],
                      _buildWebReceiverCard(ctrl),
                      const SizedBox(height: 16),
                      _buildDlnaSection(ctrl),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRemoteControlCard(CastController ctrl) {
    final totalSecs = ctrl.duration.inSeconds > 0
        ? ctrl.duration.inSeconds.toDouble()
        : (ctrl.position.inSeconds > 0
            ? ctrl.position.inSeconds.toDouble()
            : 1.0);
    final currentSecs = (_draggingSeekSeconds ?? ctrl.position.inSeconds.toDouble())
        .clamp(0.0, totalSecs);
    final isPlaying = ctrl.playbackState == CastPlaybackState.playing;
    final currentVol = (_draggingVolume ?? ctrl.volume).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isPlaying ? AppColors.accent : AppColors.online,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ctrl.activeTargetName ?? 'Dispositivo Cast',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _stateLabel(ctrl.playbackState),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ctrl.activeTitle ?? widget.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.textPrimary,
              overlayColor: AppColors.textPrimary.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: currentSecs,
              min: 0,
              max: totalSecs,
              onChanged: (v) => setState(() => _draggingSeekSeconds = v),
              onChangeEnd: (v) {
                setState(() => _draggingSeekSeconds = null);
                ctrl.seek(Duration(seconds: v.round()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(Duration(seconds: currentSecs.round())),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _formatDuration(ctrl.duration),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '-10s',
                onPressed: () {
                  final target = ctrl.position - const Duration(seconds: 10);
                  ctrl.seek(target.isNegative ? Duration.zero : target);
                },
                iconSize: 30,
                color: AppColors.textPrimary,
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 54,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    foregroundColor: AppColors.onPrimaryAction,
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => isPlaying ? ctrl.pause() : ctrl.play(),
                  child: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              IconButton(
                tooltip: '+10s',
                onPressed: () {
                  ctrl.seek(ctrl.position + const Duration(seconds: 10));
                },
                iconSize: 30,
                color: AppColors.textPrimary,
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.volume_down_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    activeTrackColor: AppColors.textPrimary,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.textPrimary,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: currentVol,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => setState(() => _draggingVolume = v),
                    onChangeEnd: (v) {
                      setState(() => _draggingVolume = null);
                      ctrl.setVolume(v);
                    },
                  ),
                ),
              ),
              const Icon(
                Icons.volume_up_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: const Text('Disconnetti'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebReceiverCard(CastController ctrl) {
    final pairingCode = ctrl.pairingCode ?? '----';
    final portCode = ctrl.portCode;
    final fullCode = portCode != null ? '$pairingCode-$portCode' : pairingCode;
    final receiverUrl = ctrl.receiverUrl ?? 'Avvio server locale...';
    final isConnected = ctrl.isWebReceiverConnected;
    final isCastingToWeb =
        ctrl.isCasting && ctrl.targetType == CastTargetType.webReceiver;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tv_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Web Receiver',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color:
                            isConnected ? AppColors.online : AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Connesso' : 'In attesa',
                      style: TextStyle(
                        color: isConnected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Apri il link sul browser della TV o del PC sulla stessa rete Wi-Fi.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CODICE PAIRING',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fullCode,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copia codice',
                  onPressed: ctrl.pairingCode == null
                      ? null
                      : () => _copyToClipboard(fullCode, 'Codice'),
                  icon: const Icon(
                    Icons.copy_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    receiverUrl,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copia URL',
                  onPressed: ctrl.receiverUrl == null
                      ? null
                      : () => _copyToClipboard(ctrl.receiverUrl!, 'URL'),
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startingCast || isCastingToWeb
                  ? null
                  : () => _startCast(),
              icon: _startingCast
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimaryAction,
                      ),
                    )
                  : const Icon(Icons.cast_rounded, size: 18),
              label: Text(
                isCastingToWeb
                    ? 'In riproduzione su Web Receiver'
                    : 'Trasmetti su Web Receiver',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDlnaSection(CastController ctrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.connected_tv_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Smart TV / DLNA',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (ctrl.isDiscoveringDlna)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Aggiorna dispositivi',
                  onPressed: () => ctrl.discoverDlna(),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (ctrl.dlnaDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                ctrl.isDiscoveringDlna
                    ? 'Ricerca Smart TV sulla rete Wi-Fi...'
                    : 'Nessuna TV DLNA trovata. Tocca aggiorna o usa il Web Receiver.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...ctrl.dlnaDevices.map((device) {
              final isActive = ctrl.isCasting &&
                  ctrl.targetType == CastTargetType.dlna &&
                  ctrl.activeDlnaDevice == device;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _startingCast
                      ? null
                      : () => _startCast(dlnaDevice: device),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.surfaceElevated
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            ? AppColors.textSecondary
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isActive
                              ? Icons.cast_connected_rounded
                              : Icons.tv_rounded,
                          color: isActive
                              ? AppColors.online
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.friendlyName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                device.subtitle,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isActive
                              ? Icons.check_circle_rounded
                              : Icons.chevron_right_rounded,
                          color: isActive
                              ? AppColors.online
                              : AppColors.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stateLabel(CastPlaybackState state) {
    switch (state) {
      case CastPlaybackState.playing:
        return 'In riproduzione';
      case CastPlaybackState.paused:
        return 'In pausa';
      case CastPlaybackState.buffering:
        return 'Caricamento...';
      case CastPlaybackState.ended:
        return 'Terminato';
      case CastPlaybackState.error:
        return 'Errore';
      case CastPlaybackState.idle:
        return 'Pronto';
    }
  }
}
