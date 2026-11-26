// Uji unit OpencodeClient — semua lewat FakeRuntimeBridge manual (tanpa
// mockito, tanpa jaringan). Kontrak endpoint: docs/OPENCODE_CLIENT_CONTRACT.md.
//
// RuntimeBridge dipakai sebagai superclass konkret oleh OpencodeClient, jadi
// FakeRuntimeBridge menimpa httpProxy (satu-satunya metode jaringan yang
// dipakai klien) dan urlJoin / startServer bila diperlukan.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/models/api_result.dart';
import 'package:oagents/models/session_summary.dart';
import 'package:oagents/services/runtime_bridge.dart';
import 'package:oagents/services/opencode_client.dart';

/// Fake manual: merekam setiap permintaan proxy lalu membalas dari daftar
/// antrean respons. Bila antrean habis, membalas 500 agar retry dapat dites.
class FakeRuntimeBridge extends RuntimeBridge {
  FakeRuntimeBridge() : super();

  /// Antrean respons; tiap [ProxyResponse] diambil sekali lalu dibuang.
  final List<ProxyResponse> queue = <ProxyResponse>[];

  /// Log permintaan (method, path, body) untuk assertion.
  final List<(String, String, String?)> calls = <(String, String, String?)>[];

  @override
  Future<ProxyResponse> httpProxy({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls.add((method, path, body));
    if (queue.isEmpty) {
      return const ProxyResponse(status: 500, body: 'antrean kosong');
    }
    return queue.removeAt(0);
  }
}

ProxyResponse ok(String body) => ProxyResponse(status: 200, body: body);

void main() {
  late FakeRuntimeBridge bridge;
  late OpencodeClient client;

  setUp(() {
    bridge = FakeRuntimeBridge();
    // Jeda retry nol supaya test followLog tidak menunggu 2 detik nyata.
    client = OpencodeClient(
      bridge: bridge,
      followRetryDelay: const Duration(milliseconds: 1),
    );
  });

  group('OpencodeClient — getInfo (GET /api/info)', () {
    test('parsing respons info server menjadi map', () async {
      bridge.queue.add(ok('{"version":"2.4.1","name":"opencode"}'));
      final res = await client.getInfo();
      final value = res.orNull!;
      expect(value['version'], '2.4.1');
      expect(bridge.calls.single, ('GET', '/api/info', null));
    });

    test('respons non-objek (array) menjadi ApiErr dengan fallback kosong',
        () async {
      bridge.queue.add(ok('[1,2,3]'));
      final res = await client.getInfo();
      expect(res, isA<ApiErr<Map<String, dynamic>>>());
      expect(res.orDefault, isEmpty);
    });

    test('respons 401 → ApiErr berisi pesan autentikasi', () async {
      bridge.queue.add(const ProxyResponse(status: 401, body: 'unauthorized'));
      final res = await client.getInfo();
      final err = res as ApiErr<Map<String, dynamic>>;
      expect(err.code, 401);
      expect(err.message, contains('Autentikasi gagal'));
      expect(err.fallback, isEmpty);
    });
  });

  group('OpencodeClient — createSession (POST /api/session)', () {
    test('respons sessionID → ApiOk berisi id', () async {
      bridge.queue.add(ok('{"sessionID":"ses_123"}'));
      final res = await client.createSession();
      expect(res.orDefault, 'ses_123');
      final call = bridge.calls.single;
      expect(call.$1, 'POST');
      expect(call.$2, '/api/session');
    });

    test('respons tanpa sessionID → ApiErr', () async {
      bridge.queue.add(ok('{}'));
      final res = await client.createSession();
      expect(res, isA<ApiErr<String>>());
      expect(res.orDefault, '');
    });

    test('galat proxy → ApiErr dengan fallback string kosong', () async {
      bridge.queue.add(const ProxyResponse(status: 500, body: 'busuk'));
      final res = await client.createSession();
      expect(res, isA<ApiErr<String>>());
      expect((res as ApiErr<String>).code, 500);
    });
  });

  group('OpencodeClient — listSessions (GET /api/session)', () {
    test('format polos (array) terparse menjadi SessionSummary', () async {
      bridge.queue.add(ok(
        '[{"id":"a1","title":"Riset","updatedAt":1730000000000},'
        '{"sessionID":"b2","name":"Debug"}]',
      ));
      final res = await client.listSessions();
      final list = res.orDefault;
      expect(list, hasLength(2));
      expect(list[0].id, 'a1');
      expect(list[0].title, 'Riset');
      expect(list[1].id, 'b2');
      expect(list[1].title, 'Debug');
    });

    test('format berhalaman {sessions: []} juga didukung', () async {
      bridge.queue.add(ok(
        '{"sessions":[{"id":"x","title":"Pagi"},{"id":"y","title":"Siang"}]}',
      ));
      final res = await client.listSessions();
      expect(res.orDefault, hasLength(2));
      expect(res.orDefault.map((s) => s.title), containsAll(['Pagi', 'Siang']));
    });

    test('galat 502 → ApiErr fallback list kosong', () async {
      bridge.queue.add(const ProxyResponse(status: 502, body: 'skill gagal'));
      final res = await client.listSessions();
      expect(res, isA<ApiErr<List<SessionSummary>>>());
      expect(res.orDefault, isEmpty);
    });
  });

  group('OpencodeClient — sendPrompt & waitForSession', () {
    test('sendPrompt sukses mengirim body JSON berisi text', () async {
      bridge.queue.add(ok('{"infoID":"i1"}'));
      final res = await client.sendPrompt('s1', 'Halo agent');
      expect(res, isA<ApiOk<Map<String, dynamic>>>());
      final body = bridge.calls.single.$3!;
      expect(body, contains('Halo agent'));
      expect(body, contains('"resume":true'));
    });

    test('sendPrompt error 409 → ApiErr konflik sesi', () async {
      bridge.queue.add(const ProxyResponse(status: 409, body: 'conflict'));
      final res = await client.sendPrompt('s1', 'ulang');
      final err = res as ApiErr<Map<String, dynamic>>;
      expect(err.code, 409);
      expect(err.message, contains('Konflik'));
    });

    test('waitForSession mengembalikan ApiOk(true) pada status 204', () async {
      bridge.queue.add(const ProxyResponse(status: 204, body: ''));
      final res = await client.waitForSession('s1');
      expect(res.orDefault, isTrue);
      expect(bridge.calls.single.$2, '/api/session/s1/wait');
    });
  });

  group('OpencodeClient — decidePermission (varian endpoint)', () {
    test('varian utama POST /api/permission langsung diterima', () async {
      bridge.queue.add(ok('{}'));
      final res = await client.decidePermission(
        sessionId: 's1',
        requestId: 'r9',
        allowed: true,
      );
      expect(res.orDefault, isTrue);
      expect(bridge.calls.single.$2, '/api/permission');
    });

    test('varian fallback per-sesi saat utama 404', () async {
      bridge.queue
        ..add(const ProxyResponse(status: 404, body: 'nope'))
        ..add(ok('{}'));
      final res = await client.decidePermission(
        sessionId: 's2',
        requestId: 'r1',
        allowed: false,
      );
      expect(res.orDefault, isTrue);
      expect(bridge.calls[0].$2, '/api/permission');
      expect(bridge.calls[1].$2, '/api/session/s2/permission/r1/reply');
    });

    test('varian kedua juga 404 → coba POST /api/session/:id/permission',
        () async {
      bridge.queue
        ..add(const ProxyResponse(status: 404, body: 'nope'))
        ..add(const ProxyResponse(status: 404, body: 'nope'))
        ..add(ok('{}'));
      final res = await client.decidePermission(
        sessionId: 's3',
        requestId: 'r2',
        allowed: true,
      );
      expect(res.orDefault, isTrue);
      expect(bridge.calls[2].$2, '/api/session/s3/permission');
    });

    test('semua varian gagal 500 → ApiErr berisi kode status', () async {
      bridge.queue
        ..add(const ProxyResponse(status: 500, body: 'down'))
        ..add(const ProxyResponse(status: 500, body: 'down'))
        ..add(const ProxyResponse(status: 500, body: 'down'));
      final res = await client.decidePermission(
        sessionId: 's4',
        requestId: 'r3',
        allowed: false,
      );
      expect(res, isA<ApiErr<bool>>());
      expect((res as ApiErr<bool>).code, 500);
      expect(res.fallback, isFalse);
    });
  });

  group('OpencodeClient — followLog (SSE via proxy berulang)', () {
    test('404 → stream berhenti (sesi hilang, tanpa retry)', () async {
      bridge.queue.add(const ProxyResponse(status: 404, body: ''));
      final events = <Map<String, dynamic>>[];
      await for (final ev in client.followLog('s-hilang')) {
        events.add(ev);
      }
      expect(events, isEmpty);
      expect(bridge.calls.map((c) => c.$2), everyElement(contains('/log')));
    });

    test('500 lalu 200 → event SSE terparse dan cursor after maju', () async {
      final sse = 'event: session.execution.partial\n'
          'data: {"seq":42,"delta":"Ha"}\n\n';
      bridge.queue
        ..add(const ProxyResponse(status: 503, body: 'unavailable'))
        ..add(ok(sse));
      final events = <Map<String, dynamic>>[];
      // Hentikan stream setelah event pertama supaya loop tak berjalan abadi.
      final sub = client.followLog('s1', onRetry: (d) {}).listen(events.add);
      while (events.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      unawaited(sub.cancel());
      expect(events.first['event'], 'session.execution.partial');
      expect(events.first['json']['delta'], 'Ha');
      // Permintaan kedua membawa kursor setelah event seq 42.
      expect(bridge.calls.last.$2, contains('after=42'));
    });

    test('urlJoin / pembentukan path permintaan konsisten', () async {
      bridge.queue.add(ok('data: kosong\n\n'));
      final sub = client.followLog('abc').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      unawaited(sub.cancel());
      expect(
        bridge.calls.first.$2,
        '/api/session/abc/log?follow=true',
      );
    });
  });

  group('OpencodeClient — katalog model & agent', () {
    test('listModels format {models: []} terparse', () async {
      bridge.queue.add(ok(
        '{"models":[{"id":"claude-sonnet","provider":"anthropic"},'
        '{"id":"gpt","provider":"openai"}]}',
      ));
      final res = await client.listModels();
      final models = res.orDefault;
      expect(models, hasLength(2));
      expect(models.first['id'], 'claude-sonnet');
    });

    test('listModels fallback: array polos juga diterima', () async {
      bridge.queue.add(ok('[{"id":"m1"},{"id":"m2"}]'));
      final res = await client.listModels();
      expect(res.orDefault, hasLength(2));
    });

    test('listAgents format {agents: []} terparse', () async {
      bridge.queue.add(ok(
        '{"agents":[{"name":"build"},{"name":"plan"}]}',
      ));
      final res = await client.listAgents();
      final agents = res.orDefault;
      expect(agents, hasLength(2));
      expect(agents.map((a) => a['name']), containsAll(['build', 'plan']));
    });

    test('listAgents galat 404 → ApiErr fallback kosong', () async {
      bridge.queue.add(const ProxyResponse(status: 404, body: ''));
      final res = await client.listAgents();
      expect(res, isA<ApiErr<List<Map<String, dynamic>>>>());
      expect(res.orDefault, isEmpty);
    });
  });

  group('OpencodeClient — httpProxy retry saat 500 (retry log SSE)', () {
    test('httpProxy 500 diulang klien sampai dapat 200 (retry followLog)',
        () async {
      final sse = 'data: {"seq":1}\n\n';
      bridge.queue
        ..add(const ProxyResponse(status: 500, body: 'galat internal'))
        ..add(const ProxyResponse(status: 500, body: 'galat internal'))
        ..add(ok(sse));
      final retryDetails = <String>[];
      final events = <Map<String, dynamic>>[];
      final sub =
          client.followLog('s5', onRetry: retryDetails.add).listen(events.add);
      while (events.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      unawaited(sub.cancel());
      expect(events, isNotEmpty);
      expect(retryDetails.where((d) => d.contains('500')).length,
          greaterThanOrEqualTo(1));
    });
  });
}
