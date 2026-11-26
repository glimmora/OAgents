import 'package:flutter/material.dart';

import 'package:oagents/models/api_result.dart';
import 'package:oagents/models/session_summary.dart';
import 'package:oagents/services/chat_controller.dart';
import 'package:oagents/services/opencode_client.dart';
import 'package:oagents/widgets/status_card.dart';
import 'package:provider/provider.dart';

/// Layar daftar sesi: `listSessions`, tap → `openSession` (getMessages).
/// Umpan balik galat tampil sebagai kartu status inline di daftar.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  bool _loading = false;
  List<SessionSummary> _sessions = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  OpencodeClient get _client => context.read<OpencodeClient>();

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _client.listSessions();
    switch (res) {
      case ApiOk(value: final list):
        _sessions = list;
        _error = null;
      case ApiErr(:final message):
        _sessions = const [];
        _error = message;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _open(String id, String title) async {
    final controller = context.read<ChatController>();
    await controller.openSession(id, title: title);
    if (!mounted) return;
    // Umpan balik pembukaan sesi tampil sebagai kartu status inline di
    // daftar pesan; pengguna berpindah ke tab Chat secara manual.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesi'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            StatusCard(
              title: controller.sessionId == null
                  ? 'Sesi aktif: belum ada'
                  : 'Sesi aktif: ${controller.sessionId}',
              detail: 'Tap salah satu sesi untuk membukanya dan memuat '
                  'pesannya; tab Chat otomatis melanjutkan percakapan.',
              icon: 'session',
              compact: true,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              StatusCard(
                title: 'Gagal memuat daftar sesi',
                detail: '$_error. Pastikan server opencode berjalan di tab '
                    'Runtime, lalu tarik untuk menyegarkan.',
                icon: 'error',
                tone: StatusTone.error,
              )
            else if (_sessions.isEmpty)
              const StatusCard(
                title: 'Belum ada sesi',
                detail: 'Daftar kosong. Kirim pesan pertama di tab Chat untuk '
                    'membuat sesi baru.',
                icon: 'info',
              )
            else
              for (final s in _sessions)
                _SessionTile(
                  session: s,
                  active: s.id == controller.sessionId,
                  onTap: () => _open(s.id, s.title),
                ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.active,
    required this.onTap,
  });

  final SessionSummary session;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      color: active
          ? scheme.primary.withOpacity(0.14)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active ? scheme.primary.withOpacity(0.6) : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: Icon(
            active ? Icons.chat_bubble : Icons.chat_bubble_outline,
            color: scheme.primary,
          ),
          title: Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${session.id} • ${session.updatedLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withOpacity(0.6),
            ),
          ),
          trailing: active
              ? Text(
                  'aktif',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
