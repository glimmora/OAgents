import 'dart:convert';

import 'package:oagents/models/api_result.dart';
import 'package:oagents/models/session_summary.dart';
import 'package:oagents/services/runtime_bridge.dart';
import 'package:oagents/services/sse_parser.dart';

/// Klien REST opencode — SEMUA lewat `RuntimeBridge.httpProxy`
/// (kontrak OPENCODE_CLIENT_CONTRACT.md; tanpa paket `http`).
///
/// Metode tipis tanpa logika provider: tidak ada URL/model/api-key di sini.
class OpencodeClient {
  OpencodeClient({
    required this.bridge,
    this.followRetryDelay = const Duration(seconds: 2),
  });
  final RuntimeBridge bridge;

  /// Jeda polling ulang `followLog` bila proxy memutus aliran SSE.
  /// Dapat disuntik pengujian agar tidak menunggu jeda nyata.
  final Duration followRetryDelay;
  // ------------------------------------------------------------ dasar

  /// `GET /api/info` — healthcheck server.
  Future<ApiResult<Map<String, dynamic>>> getInfo() async {
    final res = await _fetchJson('GET', '/api/info');
    return switch (res) {
      ApiOk(:final value) when value is Map<String, dynamic> => ApiOk(value),
      ApiOk() => const ApiErr(
          'Respons /api/info bukan objek JSON.',
          fallback: <String, dynamic>{},
        ),
      ApiErr(:final message, :final code) => ApiErr(
          message,
          code: code,
          fallback: const <String, dynamic>{},
        ),
    };
  }

  // ------------------------------------------------------------ sesi

  /// `POST /api/session` — buat sesi baru, mengembalikan `{sessionID}`.
  Future<ApiResult<String>> createSession() async {
    final res = await _fetchJson('POST', '/api/session');
    if (res is ApiErr) {
      return ApiErr(res.message, code: res.code, fallback: '');
    }
    final value = res is ApiOk ? res.value : null;
    if (value is! Map) {
      return const ApiErr('Bentuk respons sesi tidak sesuai.', fallback: '');
    }
    final id = (value['sessionID'] ?? value['id'] ?? value['session_id'] ?? '')
        .toString();
    if (id.isEmpty) {
      return const ApiErr('Respons server tanpa sessionID.', fallback: '');
    }
    return ApiOk(id);
  }

  /// `GET /api/session` — daftar sesi (dukung format berhalaman & polos).
  Future<ApiResult<List<SessionSummary>>> listSessions() async {
    final res = await _fetchJson('GET', '/api/session');
    return switch (res) {
      ApiOk(:final value) => ApiOk(_parseSessionList(value)),
      ApiErr(:final message, :final code) => ApiErr(
          message,
          code: code,
          fallback: const <SessionSummary>[],
        ),
    };
  }

  List<SessionSummary> _parseSessionList(dynamic decoded) {
    List<dynamic>? items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map) {
      final wrap = decoded['sessions'] ?? decoded['items'] ?? decoded['data'];
      if (wrap is List) items = wrap;
    }
    if (items == null) return const [];
    return [
      for (final it in items)
        if (it is Map) SessionSummary.fromJson(_mapOf(it)),
    ];
  }

  /// `GET /api/session/:id/message` — pesan sesi.
  Future<ApiResult<List<Map<String, dynamic>>>> getMessages(
    String sessionId,
  ) async {
    final res = await _fetchJson('GET', '/api/session/$sessionId/message');
    return switch (res) {
      ApiOk(:final value) => ApiOk(_parseMessageList(value)),
      ApiErr(:final message, :final code) => ApiErr(
          message,
          code: code,
          fallback: const <Map<String, dynamic>>[],
        ),
    };
  }

  List<Map<String, dynamic>> _parseMessageList(dynamic decoded) {
    List<dynamic>? items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map) {
      final wrap = decoded['messages'] ?? decoded['items'] ?? decoded['data'];
      if (wrap is List) items = wrap;
    }
    if (items == null) return const [];
    return [
      for (final it in items)
        if (it is Map) _mapOf(it)
    ];
  }

  /// `POST /api/session/:id/prompt` — kirim prompt.
  /// Prompt hanya ter-queue; hasil nyata dibaca lewat SSE/wait.
  Future<ApiResult<Map<String, dynamic>>> sendPrompt(
    String sessionId,
    String text, {
    bool resume = true,
  }) async {
    final res = await _fetchJson(
      'POST',
      '/api/session/$sessionId/prompt',
      body: jsonEncode(<String, dynamic>{'text': text, 'resume': resume}),
    );
    return switch (res) {
      ApiOk(:final value) when value is Map<String, dynamic> => ApiOk(value),
      ApiOk() => const ApiErr(
          'Bentuk respons prompt tidak sesuai.',
          fallback: <String, dynamic>{},
        ),
      ApiErr(:final message, :final code) => ApiErr(
          message,
          code: code,
          fallback: const <String, dynamic>{},
        ),
    };
  }

  /// `POST /api/session/:id/wait` — tunggu eksekusi sesi selesai (204).
  Future<ApiResult<bool>> waitForSession(String sessionId) async {
    final res = await _request('POST', '/api/session/$sessionId/wait');
    if (res.isOk) return const ApiOk(true);
    return ApiErr(_httpMessage(res), code: res.status, fallback: false);
  }

  // ------------------------------------------------------------ log SSE

  /// `GET /api/session/:id/log?follow=true` — SSE event sesi:
  /// `session.execution.*`, teks parsial, panggilan tool, permintaan izin.
  ///
  /// `httpProxy` tidak menjaga koneksi terbuka, jadi stream ini memanggil
  /// proxy berulang dan menyuapkan body ke [SseParser]; bila proxy
  /// mengembalikan galat, jeda lalu ulangi. Kursor `after` menyambung
  /// event yang sudah dibaca pada percobaan sebelumnya.
  Stream<Map<String, dynamic>> followLog(
    String sessionId, {
    String? after,
    void Function(String detail)? onRetry,
  }) async* {
    String? cursor = after;
    while (true) {
      final path = StringBuffer('/api/session/$sessionId/log?follow=true');
      if (cursor != null && cursor.isNotEmpty) path.write('&after=$cursor');
      ProxyResponse res;
      try {
        res = await bridge.httpProxy(method: 'GET', path: path.toString());
      } on BridgeException catch (e) {
        onRetry?.call(e.message);
        await Future<void>.delayed(followRetryDelay);
        continue;
      }
      if (res.status == 404) return; // sesi hilang — berhenti mengikuti.
      if (res.status >= 500) {
        onRetry?.call('Server galat ${res.status}, mencoba ulang…');
        await Future<void>.delayed(followRetryDelay);
        continue;
      }
      final events = <Map<String, dynamic>>[];
      final parser = SseParser(events.add);
      parser.push(res.body);
      parser.close();
      for (final ev in events) {
        final map = sseEventToMap(ev);
        cursor = _advanceCursor(cursor, map);
        yield map;
      }
      // Body habis = aliran terputus → jeda lalu sambung lagi.
      await Future<void>.delayed(followRetryDelay);
    }
  }

  String? _advanceCursor(String? current, Map<String, dynamic> event) {
    final json = event['json'];
    if (json is Map) {
      final seq = json['seq'] ?? json['sequence'] ?? json['id'];
      if (seq != null) return seq.toString();
    }
    final id = event['id'];
    return id?.toString() ?? current;
  }

  // ------------------------------------------------------------ izin

  /// `POST /api/permission` — keputusan pengguna dari kartu izin inline.
  /// Bila versi server memakai endpoint per-sesi, fallback otomatis.
  Future<ApiResult<bool>> decidePermission({
    required String sessionId,
    required String requestId,
    required bool allowed,
  }) async {
    final payload = jsonEncode(<String, dynamic>{
      'requestID': requestId,
      'sessionID': sessionId,
      'response': allowed ? 'allow' : 'deny',
      'allowed': allowed,
    });
    // Bentuk kontrak: POST /api/permission.
    var res = await _request('POST', '/api/permission', body: payload);
    if (!res.isOk && res.status == 404) {
      // Varian per-sesi: POST /api/session/:id/permission/:requestID/reply.
      res = await _request(
        'POST',
        '/api/session/$sessionId/permission/$requestId/reply',
        body: payload,
      );
    }
    if (!res.isOk && res.status == 404) {
      // Varian: POST /api/session/:id/permission.
      res = await _request(
        'POST',
        '/api/session/$sessionId/permission',
        body: payload,
      );
    }
    if (res.isOk) return const ApiOk(true);
    return ApiErr(_httpMessage(res), code: res.status, fallback: false);
  }

  // ------------------------------------------------------------ katalog

  /// `GET /api/model` — daftar model aktif.
  Future<ApiResult<List<Map<String, dynamic>>>> listModels() async {
    return _getList('/api/model', 'models');
  }

  /// `GET /api/agent` — daftar agent aktif.
  Future<ApiResult<List<Map<String, dynamic>>>> listAgents() async {
    return _getList('/api/agent', 'agents');
  }

  Future<ApiResult<List<Map<String, dynamic>>>> _getList(
    String path,
    String wrapKey,
  ) async {
    final res = await _fetchJson('GET', path);
    return switch (res) {
      ApiOk(:final value) => ApiOk(_parseWrapList(value, wrapKey)),
      ApiErr(:final message, :final code) => ApiErr(
          message,
          code: code,
          fallback: const <Map<String, dynamic>>[],
        ),
    };
  }

  List<Map<String, dynamic>> _parseWrapList(
    dynamic decoded,
    String wrapKey,
  ) {
    List<dynamic>? items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map) {
      final wrap = decoded[wrapKey] ?? decoded['items'] ?? decoded['data'];
      if (wrap is List) items = wrap;
    }
    if (items == null) return const [];
    return [
      for (final it in items)
        if (it is Map) _mapOf(it)
    ];
  }

  // ------------------------------------------------------------ inti HTTP

  Future<ProxyResponse> _request(
    String method,
    String path, {
    String? body,
  }) async {
    return bridge.httpProxy(
      method: method,
      path: path,
      body: body,
      headers: {
        if (body != null) 'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
  }

  /// Satu panggilan proxy + decode JSON — sumber semua metode publik.
  Future<ApiResult<dynamic>> _fetchJson(
    String method,
    String path, {
    String? body,
  }) async {
    try {
      final res = await _request(method, path, body: body);
      if (!res.isOk) {
        return ApiErr(_httpMessage(res), code: res.status, fallback: null);
      }
      final decoded = _decodeBody(res.body);
      if (decoded == null) {
        return ApiErr(
          'Respons bukan JSON valid.',
          code: res.status,
          fallback: null,
        );
      }
      return ApiOk(decoded);
    } on BridgeException catch (e) {
      return ApiErr(e.message, fallback: null);
    }
  }

  static dynamic _decodeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return const <String, dynamic>{};
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  static String _httpMessage(ProxyResponse res) {
    switch (res.status) {
      case 400:
        return 'Permintaan ditolak server (400).';
      case 401:
        return 'Autentikasi gagal — periksa API key provider (401).';
      case 404:
        return 'Sumber daya tidak ditemukan (404).';
      case 409:
        return 'Konflik status sesi (409).';
      case 502:
        return 'Server gagal memuat skill (502).';
      default:
        final snippet =
            res.body.length > 160 ? res.body.substring(0, 160) : res.body;
        return 'Galat HTTP ${res.status}: $snippet';
    }
  }

  static Map<String, dynamic> _mapOf(Map raw) =>
      raw.map((k, v) => MapEntry(k.toString(), v));
}
