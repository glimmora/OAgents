import 'package:flutter/foundation.dart';

/// Tahap siklus hidup runtime lingkungan (rootfs + server opencode).
enum RuntimeStage {
  idle,
  downloading,
  verifying,
  extracting,
  installing,
  booting,
  ready,
  error,
}

/// Label Indonesia untuk tiap tahap — dipakai kartu status runtime.
String stageLabel(RuntimeStage stage) {
  switch (stage) {
    case RuntimeStage.idle:
      return 'Menganggur';
    case RuntimeStage.downloading:
      return 'Mengunduh rootfs';
    case RuntimeStage.verifying:
      return 'Memverifikasi checksum';
    case RuntimeStage.extracting:
      return 'Mengekstrak arsip';
    case RuntimeStage.installing:
      return 'Memasang opencode';
    case RuntimeStage.booting:
      return 'Menjalankan server';
    case RuntimeStage.ready:
      return 'Siap';
    case RuntimeStage.error:
      return 'Galat';
  }
}

/// Parser tahap dari string event `oagents/progress` maupun hasil metode.
RuntimeStage stageFromString(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'downloading':
      return RuntimeStage.downloading;
    case 'verifying':
      return RuntimeStage.verifying;
    case 'extracting':
      return RuntimeStage.extracting;
    case 'installing':
      return RuntimeStage.installing;
    case 'booting':
      return RuntimeStage.booting;
    case 'ready':
      return RuntimeStage.ready;
    case 'error':
      return RuntimeStage.error;
    default:
      return RuntimeStage.idle;
  }
}

/// Snapshot status pemasangan rootfs + biner opencode (metode `rootfsStatus`).
@immutable
class RootfsStatus {
  const RootfsStatus({
    required this.installed,
    required this.version,
    required this.sizeMB,
    required this.ok,
  });

  factory RootfsStatus.fromJson(Map<String, dynamic> json) {
    return RootfsStatus(
      installed: json['installed'] == true,
      version: _asString(json['version']),
      sizeMB: _asDouble(json['sizeMB']),
      ok: json['ok'] == true,
    );
  }

  final bool installed;
  final String version;
  final double sizeMB;
  final bool ok;

  static String _asString(Object? v) => v == null ? '' : v.toString();
  static double _asDouble(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
}

/// Snapshot status server opencode (metode `serverStatus`).
@immutable
class ServerStatus {
  const ServerStatus({
    required this.running,
    required this.pid,
    required this.port,
    required this.upMs,
  });

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    // `serverStatus` mengirim `running`; `startServer` (kontrak bridge)
    // mengirim `ok` — keduanya berarti server hidup.
    final running = json['running'] == true || json['ok'] == true;
    return ServerStatus(
      running: running,
      pid: _asInt(json['pid']),
      port: _asInt(json['port']),
      upMs: _asInt(json['upMs']),
    );
  }

  final bool running;
  final int pid;
  final int port;
  final int upMs;

  /// Durasi hidup server sebagai teks ringkas (mm:dd/jam) untuk kartu status.
  String get uptimeLabel {
    if (upMs <= 0) return '—';
    final secs = upMs ~/ 1000;
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// Satu event kemajuan instalasi dari EventChannel `oagents/progress`.
@immutable
class ProgressEvent {
  const ProgressEvent({
    required this.stage,
    required this.pct,
    required this.detail,
  });

  factory ProgressEvent.fromJson(Map<String, dynamic> json) {
    return ProgressEvent(
      stage: stageFromString(json['stage']?.toString()),
      pct: _clampPct(json['pct']),
      detail: json['detail']?.toString() ?? '',
    );
  }

  final RuntimeStage stage;
  final int pct;
  final String detail;

  static int _clampPct(Object? v) {
    final d = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (d.isNaN) return 0;
    return d.clamp(0, 100).round();
  }
}

/// Galat dari kanal native bila Kotlin mengembalikan `{ok:false, error:...}`.
@immutable
class BridgeError {
  const BridgeError(this.message);

  final String message;
}
