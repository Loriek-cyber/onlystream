import 'package:flutter/material.dart';
import 'package:onlystream/models/library.dart';
import 'package:onlystream/models/media.dart';
import 'package:onlystream/services/config_service.dart';
import 'package:onlystream/theme/app_theme.dart';

class MediaNetworkImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final IconData fallbackIcon;
  final BorderRadius? borderRadius;

  const MediaNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.movie_outlined,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = url?.trim();
    Widget child;
    if (trimmed == null || trimmed.isEmpty) {
      child = _FallbackBox(icon: fallbackIcon);
    } else {
      child = Image.network(
        trimmed,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => _FallbackBox(icon: fallbackIcon),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const ColoredBox(color: AppColors.surfaceElevated);
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}

class _FallbackBox extends StatelessWidget {
  final IconData icon;

  const _FallbackBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(icon, color: AppColors.textMuted, size: 28),
      ),
    );
  }
}

class PosterMediaCard extends StatelessWidget {
  final MediaSummary item;
  final VoidCallback onTap;
  final double? width;

  const PosterMediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      item.kindLabel,
      if (item.year != null && item.year!.isNotEmpty) item.year!,
    ];

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: MediaNetworkImage(
                  url: item.poster,
                  fallbackIcon: item.kind == MediaKind.tv
                      ? Icons.tv_outlined
                      : Icons.movie_outlined,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              metaParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContinueWatchingCard extends StatelessWidget {
  final LibraryItemView item;
  final VoidCallback onTap;
  final VoidCallback? onInfoTap;

  const ContinueWatchingCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final ep = item.episodeLabel;
    final subtitle = <String>[
      ?ep,
      if (item.year != null && item.year!.isNotEmpty && ep == null) item.year!,
      if (item.hasNewEpisodes) 'Nuovi episodi',
    ].join(' · ');

    return SizedBox(
      width: 248,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaNetworkImage(
                      url: item.backdrop ?? item.poster,
                      fallbackIcon: Icons.play_circle_outline_rounded,
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.65),
                            ],
                            stops: const [0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xAA0B0B0D),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: AppColors.textPrimary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    if (onInfoTap != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0x990B0B0D),
                          ),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppColors.textPrimary,
                          ),
                          tooltip: 'Dettagli',
                          onPressed: onInfoTap,
                        ),
                      ),
                    if (item.progressRatio > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: 3,
                          child: LinearProgressIndicator(
                            value: item.progressRatio,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (item.hasNewEpisodes) ...[
                    const _TinyRedDot(),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TinyRedDot extends StatelessWidget {
  const _TinyRedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}

class ServerStatusPill extends StatelessWidget {
  final ConfigService config;
  final VoidCallback onTap;

  const ServerStatusPill({
    super.key,
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final online = config.status.isOnline;
    final label = config.isChecking
        ? 'Verifica...'
        : online
            ? (config.serverMode == 'local' ? 'Locale' : 'Connesso')
            : 'Offline';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: config.isChecking
                    ? AppColors.textSecondary
                    : (online ? AppColors.online : AppColors.accent),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
