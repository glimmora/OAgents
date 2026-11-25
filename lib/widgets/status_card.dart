import 'package:flutter/material.dart';

/// Kartu status inline reusable — SEMUA umpan balik UI OAgents memakai
/// kartu ini di dalam daftar pesan atau halaman runtime; tidak ada
/// popup notifikasi melayang.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    this.detail,
    this.icon,
    this.progress,
    this.tone = StatusTone.info,
    this.trailing,
    this.onTap,
    this.compact = false,
  });

  final String title;
  final String? detail;

  /// Simbol singkat (`ok`, `warn`, `run`, `info`) → ikon Material.
  final String? icon;

  /// 0..100 — bila non-null, tampil LinearProgressIndicator di bawah detail.
  final int? progress;

  final StatusTone tone;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _toneColor(scheme);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(_iconData(icon!), color: color, size: 22),
                    ),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 13 : 15,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  detail!,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.75),
                    fontSize: compact ? 12 : 13,
                    height: 1.35,
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress == 0 ? null : progress! / 100,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _toneColor(ColorScheme scheme) {
    switch (tone) {
      case StatusTone.info:
        return scheme.primary;
      case StatusTone.ok:
        return const Color(0xFF6FBF8B);
      case StatusTone.warn:
        return const Color(0xFFE0B25A);
      case StatusTone.error:
        return scheme.error;
      case StatusTone.run:
        return const Color(0xFFD4875A);
    }
  }

  static IconData _iconData(String icon) {
    switch (icon) {
      case 'ok':
        return Icons.check_circle_outline;
      case 'warn':
        return Icons.warning_amber_outlined;
      case 'error':
        return Icons.error_outline;
      case 'run':
        return Icons.play_circle_outline;
      case 'download':
        return Icons.download_outlined;
      case 'server':
        return Icons.dns_outlined;
      case 'chat':
        return Icons.chat_bubble_outline;
      case 'runtime':
        return Icons.memory_outlined;
      case 'session':
        return Icons.folder_open_outlined;
      default:
        return Icons.info_outline;
    }
  }
}

enum StatusTone { info, ok, warn, error, run }
