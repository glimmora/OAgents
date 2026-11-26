import 'package:flutter/services.dart';

import 'package:oagents/models/runtime_status.dart';
import 'package:oagents/services/credential_store.dart';

/// Pembungkus kanal native `oagents/runtime` + event `oagents/progress`.
///
/// Semua hasil JSON dari Kotlin divalidasi menjadi tipe aman
/// (lihat BRIDGE_CONTRACT.md); galat dikembalikan sebagai data —
/// kelas ini TIDAK PERNAH menampilkan popup notifikasi.
class RuntimeBridge {
  RuntimeBridge({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _methods = methodChannel ?? const MethodChannel('oagents/runtime'),
        _events = eventChannel ?? const EventChannel('oagents/progress');

  final MethodChannel _methods;
  final EventChannel _events;

  /// Menyimpan kredensial untuk disuntik sebagai env saat [startServer].
  CredentialStore? credentials;

  /// Versi opencode + URL unduhan diambil dari env.lock oleh Kotlin;
  /// Dart hanya meneruskan bila pengguna menggantinya.
  static const int defaultPort = 4096;

  // ---------------------------------------------------------------- status

  /// `rootfsStatus` — cek rootfs + biner opencode terpasang.
  Future<RootfsStatus> rootfsStatus() async {
    final raw = await _invoke('rootfsStatus');
    return RootfsStatus.fromJson(_ensureMap(raw));
  }

  /// `installRootfs` — unduh → verifikasi → ekstrak → pasang.
  /// Mengembalikan Stream event kemajuan dari `oagents/progress`.
  Stream<ProgressEvent> installRootfs({
    String? rootfsUrl,
    String? opencodeUrl,
    String? version,
  }) async* {
    final args = <String, dynamic>{
      if (rootfsUrl != null) 'rootfsUrl': rootfsUrl,
      if (opencodeUrl != null) 'opencodeUrl': opencodeUrl,
      if (version != null) 'version': version,
    };
    // Permintaan mulai: galat {ok:false} dilempar sebagai BridgeException.
    await _invoke('installRootfs', args);
    yield* progressEvents();
  }

  /// Event `oagents/progress` mentah sebagai stream bertipe aman.
  Stream<ProgressEvent> progressEvents() {
    return _events.receiveBroadcastStream().map((raw) {
      if (raw is Map) return ProgressEvent.fromJson(_mapOf(raw));
      return const ProgressEvent(stage: RuntimeStage.idle, pct: 0, detail: '');
    });
  }

  // ---------------------------------------------------------------- server

  /// `startServer` — proot + `opencode serve` dengan env kredensial dari
  /// [CredentialStore]. Dart tidak menulis kredensial ke berkas apa pun.
  Future<ServerStatus> startServer({
    int port = defaultPort,
    String? workDir,
    Map<String, String>? extraEnv,
  }) async {
    final env = <String, String>{
      ...?await credentials?.readAllEnv(),
      ...?extraEnv,
    };
    final raw = await _invoke('startServer', <String, dynamic>{
      'port': port,
      'env': env,
      if (workDir != null) 'workDir': workDir,
    });
    final map = _ensureMap(raw);
    // Kontrak bridge aturan 4: kegagalan dikembalikan {ok:false, error}
    // sebagai hasil normal — bukan PlatformException.
    if (map['ok'] == false) {
      throw BridgeException(map['error']?.toString() ?? 'startServer gagal');
    }
    return ServerStatus.fromJson(map);
  }

  /// `stopServer` — SIGTERM pid tree proot.
  Future<bool> stopServer() async {
    final raw = await _invoke('stopServer');
    return _ensureMap(raw)['ok'] == true;
  }

  /// `serverStatus` — healthcheck `/api/info` oleh Kotlin.
  Future<ServerStatus> serverStatus() async {
    final raw = await _invoke('serverStatus');
    return ServerStatus.fromJson(_ensureMap(raw));
  }

  // ------------------------------------------------------------------ exec

  /// Hasil `execInRootfs`.
  Future<ExecResult> execInRootfs(String cmd, {int timeoutMs = 30000}) async {
    final raw = await _invoke('execInRootfs', <String, dynamic>{
      'cmd': cmd,
      'timeoutMs': timeoutMs,
    });
    final map = _ensureMap(raw);
    return ExecResult(
      ok: map['ok'] == true,
      exitCode: _toInt(map['exitCode']),
      stdout: map['stdout']?.toString() ?? '',
      stderr: map['stderr']?.toString() ?? '',
    );
  }

  /// `httpProxy` — proxy ke 127.0.0.1:PORT; satu-satunya jalan jaringan
  /// Dart ke server opencode (Dart tidak boleh buka soket lokal sendiri).
  Future<ProxyResponse> httpProxy({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final raw = await _invoke('httpProxy', <String, dynamic>{
      'method': method,
      'path': path,
      if (body != null) 'body': body,
      'headers': headers,
    });
    final map = _ensureMap(raw);
    return ProxyResponse(
      status: _toInt(map['status']),
      body: map['body']?.toString() ?? '',
    );
  }

  // ---------------------------------------------------------------- helpers

  Future<dynamic> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _methods.invokeMethod<dynamic>(method, args ?? const {});
    } on PlatformException catch (e) {
      throw BridgeException(e.message ?? e.code);
    } on TypeError catch (e) {
      throw BridgeException('Tipe hasil native tidak sesuai: $e');
    } catch (e) {
      throw BridgeException('Kegagalan kanal native: $e');
    }
  }

  static Map<String, dynamic> _ensureMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    throw const BridgeException(
      'Hasil native bukan JSON objek — format bridge tidak sesuai kontrak.',
    );
  }

  static Map<String, dynamic> _mapOf(Map raw) =>
      raw.map((k, v) => MapEntry(k.toString(), v));

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// Eksepsi bridge — membungkus `{ok:false, error}` dari Kotlin.
class BridgeException implements Exception {
  const BridgeException(this.message);
  final String message;

  @override
  String toString() => 'BridgeException: $message';
}

/// Hasil `execInRootfs` — exitCode/stdout/stderr sebagai tipe aman.
class ExecResult {
  const ExecResult({
    required this.ok,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final bool ok;
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Hasil `httpProxy` — status HTTP + body string.
class ProxyResponse {
  const ProxyResponse({required this.status, required this.body});

  final int status;
  final String body;

  bool get isOk => status >= 200 && status < 300;
}
