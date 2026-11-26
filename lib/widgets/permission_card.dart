import 'package:flutter/material.dart';

import 'package:oagents/models/chat_message.dart';

/// Kartu izin tool inline: judul tool, ringkas perintah, tombol
/// Setuju/Tolak. Keputusan diteruskan lewat [onDecision] — tidak ada popup.
class PermissionCard extends StatelessWidget {
  const PermissionCard({super.key, required this.request, this.onDecision});

  final PermissionRequest request;

  /// Callback keputusan pengguna: `true` = setuju, `false` = tolak.
  /// `null` saat keputusan sudah terkirim (kartu nonaktif).
  final void Function(PermissionRequest request, bool allowed)? onDecision;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decided = request.decided;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: const Color(0xFFE0B25A).withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.shield_outlined,
                    color: Color(0xFFE0B25A),
                    size: 22,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Izin tool: ${request.tool}',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Agent ingin menjalankan perintah berikut:',
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                request.summary.isEmpty ? '—' : request.summary,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (decided == null)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onDecision == null
                          ? null
                          : () => onDecision!(request, true),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Setuju'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDecision == null
                          ? null
                          : () => onDecision!(request, false),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Tolak'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(
                    decided ? Icons.check_circle_outline : Icons.block,
                    size: 18,
                    color: decided ? const Color(0xFF6FBF8B) : scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      decided
                          ? 'Disetujuji — menunggu eksekusi lanjut.'
                          : 'Ditolak — eksekusi tool dibatalkan.',
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
