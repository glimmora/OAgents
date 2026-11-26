import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:oagents/models/runtime_status.dart';
import 'package:oagents/services/runtime_bridge.dart';
import 'package:oagents/widgets/status_card.dart';

/// Layar runtime: kartu status server + progress instalasi, tombol
/// Pasang/Mulai/Hentikan, kartu log bootstrap — semuanya inline, tanpa popup.
class RuntimeScreen extends StatefulWidget {
  const RuntimeScreen({super.key});

  @override
  State<RuntimeScreen> createState() => _RuntimeScreenState();
}

class _RuntimeScreenState extends State<RuntimeScreen> {
  final List<String> _log = <String>[];

  RootfsStatus? _rootfs;
  ServerStatus? _server;
  RuntimeStage _stage = RuntimeStage.idle;
  int _pct = 0;
  String _detail = '';
  bool _busy = false;
  String? _error;
  Timer? _poll;

  RuntimeBridge get _bridge => context.read<RuntimeBridge>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAll();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _logAdd(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() => _log.add('$stamp $line'));
    if (_log.length > 300) {
      _log.removeRange(0, _log.length - 300);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshRootfs(), _refreshServer()]);
    _startPoll();
  }

  Future<void> _refreshRootfs() async {
    try {
      final s = await _bridge.rootfsStatus();
      setState(() => _rootfs = s);
    } on BridgeException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _refreshServer() async {
    try {
      final s = await _bridge.serverStatus();
      setState(() => _server = s);
    } on BridgeException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshServer();
    });
  }

  // ------------------------------------------------------------- aksi

  Future<void> _install() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _stage = RuntimeStage.downloading;
      _pct = 0;
      _detail = 'Memulai pengunduhan rootfs Alpine…';
    });
    _logAdd('Pasang lingkungan dimulai.');
    try {
      final stream = _bridge.installRootfs();
      await for (final ev in stream) {
        _logAdd(
          '${stageLabel(ev.stage)} ${ev.pct}% — '
          '${ev.detail.isEmpty ? 'berjalan' : ev.detail}',
        );
        setState(() {
          _stage = ev.stage;
          _pct = ev.pct;
          _detail = ev.detail;
        });
      }
      _logAdd('Pemasangan lingkungan selesai.');
      setState(() {
        _stage = RuntimeStage.ready;
        _pct = 100;
      });
    } on BridgeException catch (e) {
      _logAdd('Galat: ${e.message}');
      setState(() {
        _error = e.message;
        _stage = RuntimeStage.error;
      });
    } finally {
      setState(() => _busy = false);
      await _refreshRootfs();
    }
  }

  Future<void> _startServer() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _stage = RuntimeStage.booting;
      _detail = 'Menjalankan proot + opencode serve…';
    });
    _logAdd('Mulai server opencode.');
    try {
      final s = await _bridge.startServer();
      _logAdd(
        'Server berjalan di 127.0.0.1:${s.port} (pid ${s.pid}).',
      );
      setState(() {
        _server = s;
        _stage = s.running ? RuntimeStage.ready : RuntimeStage.error;
        _detail = s.running
            ? 'Server siap menerima permintaan.'
            : 'Server tidak melaporkan berjalan.';
      });
    } on BridgeException catch (e) {
      _logAdd('Galat: ${e.message}');
      setState(() {
        _error = e.message;
        _stage = RuntimeStage.error;
      });
    } finally {
      setState(() => _busy = false);
      await _refreshServer();
    }
  }

  Future<void> _stopServer() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _logAdd('Hentikan server opencode.');
    try {
      final ok = await _bridge.stopServer();
      _logAdd(ok ? 'Server dihentikan.' : 'Server melaporkan gagal berhenti.');
      setState(
          () => _detail = ok ? 'Server dihentikan.' : 'Gagal menghentikan.');
    } on BridgeException catch (e) {
      _logAdd('Galat: ${e.message}');
      setState(() => _error = e.message);
    } finally {
      setState(() => _busy = false);
      await _refreshServer();
    }
  }

  // ------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final rootfs = _rootfs;
    final server = _server;
    final installing = _busy &&
        (_stage == RuntimeStage.downloading ||
            _stage == RuntimeStage.verifying ||
            _stage == RuntimeStage.extracting ||
            _stage == RuntimeStage.installing);

    return Scaffold(
      appBar: AppBar(title: const Text('Runtime')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          // Kartu lingkungan (rootfs + opencode).
          StatusCard(
            title: 'Lingkungan rootfs',
            detail: rootfs == null
                ? 'Memeriksa status pemasangan…'
                : rootfs.installed
                    ? 'Terpasang — opencode ${rootfs.version.isEmpty ? '(versi terkunci)' : rootfs.version}, ${rootfs.sizeMB.toStringAsFixed(0)} MB.'
                    : 'Belum terpasang. Tekan "Pasang Lingkungan" untuk '
                        'mengunduh & memasang rootfs Alpine + opencode.',
            icon: 'runtime',
            progress: installing ? _pct : null,
          ),

          // Kartu progress instalasi aktif.
          if (installing)
            StatusCard(
              title: stageLabel(_stage),
              detail: _detail.isEmpty ? 'Proses berjalan…' : _detail,
              icon: 'download',
              tone: StatusTone.run,
              progress: _pct,
            ),

          // Kartu server.
          StatusCard(
            title: 'Server opencode',
            detail: server == null
                ? 'Memeriksa status server…'
                : server.running
                    ? 'Berjalan di 127.0.0.1:${server.port} (pid '
                        '${server.pid}) — hidup ${server.uptimeLabel}.'
                    : 'Tidak berjalan. Tekan "Mulai Server" untuk '
                        'menjalankan proot + opencode serve.',
            icon: 'server',
            tone: (server?.running ?? false) ? StatusTone.ok : StatusTone.warn,
          ),

          // Kartu galat bila ada.
          if (_error != null)
            StatusCard(
              title: 'Galat runtime',
              detail: _error,
              icon: 'error',
              tone: StatusTone.error,
            ),

          // Baris tombol aksi.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _install,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Pasang Lingkungan'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || !(rootfs?.installed ?? false)
                      ? null
                      : _startServer,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Mulai Server'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy || !(server?.running ?? false) ? null : _stopServer,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Hentikan'),
                ),
              ],
            ),
          ),

          // Kartu log bootstrap.
          _LogCard(log: _log),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Log bootstrap',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 180,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: log.isEmpty
                  ? Center(
                      child: Text(
                        'Belum ada aktivitas runtime.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: log.length,
                      itemBuilder: (context, i) => Text(
                        log[i],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.8),
                          height: 1.5,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
