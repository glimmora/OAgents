// Uji unit RuntimeBridge — mock method channel JSON lewat
// TestDefaultBinaryMessengerBinding (tanpa mockito, tanpa jaringan).
// Kontrak kanal: docs/BRIDGE_CONTRACT.md (MethodChannel `oagents/runtime`,
// EventChannel `oagents/progress`).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/models/runtime_status.dart';
import 'package:oagents/services/runtime_bridge.dart';

/// Helper: mendaftarkan handler mock untuk MethodChannel `oagents/runtime`.
/// Setiap item: (namaMetode, argumen yang diharapkan, builder hasil).
typedef _Handler = (String, Map<String, dynamic>, Object? Function()?);

void _mockBridge(List<_Handler> handlers) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('oagents/runtime'), (
    MethodCall call,
  ) async {
    for (final h in handlers) {
      if (call.method == h.$1) {
        final args = call.arguments as Map<Object?, Object?>? ?? {};
        for (final e in h.$2.entries) {
          expect(args[e.key], e.value, reason: 'argumen ${e.key} salah');
        }
        final build = h.$3;
        return build == null ? null : build();
      }
    }
    fail('Metode native tidak terdaftar di mock: ${call.method}');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RuntimeBridge bridge;

  setUp(() {
    bridge = RuntimeBridge();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('oagents/runtime'), null);
  });

  group('RuntimeBridge — rootfsStatus', () {
    test('installed true terparse lengkap dari JSON', () async {
      _mockBridge([
        (
          'rootfsStatus',
          {},
          () => <String, dynamic>{
                'installed': true,
                'version': '2.4.1',
                'sizeMB': 78.5,
                'ok': true,
              }
        ),
      ]);
      final s = await bridge.rootfsStatus();
      expect(s.installed, isTrue);
      expect(s.version, '2.4.1');
      expect(s.sizeMB, 78.5);
      expect(s.ok, isTrue);
    });

    test('installed false default versi kosong & sizeMB nol', () async {
      _mockBridge([
        (
          'rootfsStatus',
          {},
          () => <String, dynamic>{
                'installed': false,
                'ok': true,
              }
        ),
      ]);
      final s = await bridge.rootfsStatus();
      expect(s.installed, isFalse);
      expect(s.version, '');
      expect(s.sizeMB, 0);
    });
  });

  group('RuntimeBridge — startServer', () {
    test('sukses {ok, pid, port} terparse ServerStatus running', () async {
      _mockBridge([
        (
          'startServer',
          {
            'port': RuntimeBridge.defaultPort,
            'env': <String, String>{},
          },
          () => <String, dynamic>{'ok': true, 'pid': 1234, 'port': 4096}
        ),
      ]);
      final s = await bridge.startServer();
      expect(s.running, isTrue);
      expect(s.pid, 1234);
      expect(s.port, 4096);
    });

    test('argumen port, env, dan workDir diteruskan ke native', () async {
      _mockBridge([
        (
          'startServer',
          {
            'port': 5000,
            'env': {'OPENCODE_OPENAI_API_KEY': 'k'},
            'workDir': '/data/tmp',
          },
          () => <String, dynamic>{'ok': true, 'pid': 9, 'port': 5000}
        ),
      ]);
      final s = await bridge.startServer(
        port: 5000,
        workDir: '/data/tmp',
        extraEnv: {'OPENCODE_OPENAI_API_KEY': 'k'},
      );
      expect(s.port, 5000);
    });

    test('galat {ok:false, error} → BridgeException terlempar', () async {
      _mockBridge([
        (
          'startServer',
          const <String, dynamic>{},
          () => <String, dynamic>{'ok': false, 'error': 'proot gagal mulai'},
        ),
      ]);
      await expectLater(
        bridge.startServer(),
        throwsA(
          isA<BridgeException>().having(
            (e) => e.message,
            'message',
            contains('proot'),
          ),
        ),
      );
    });
  });

  group('RuntimeBridge — serverStatus & stopServer', () {
    test('serverStatus running dengan pid/port/upMs', () async {
      _mockBridge([
        (
          'serverStatus',
          {},
          () => <String, dynamic>{
                'running': true,
                'pid': 77,
                'port': 4096,
                'upMs': 5400000,
              }
        ),
      ]);
      final s = await bridge.serverStatus();
      expect(s.running, isTrue);
      expect(s.uptimeLabel, '01:30:00');
    });

    test('stopServer mengembalikan true saat {ok:true}', () async {
      _mockBridge([
        ('stopServer', {}, () => <String, dynamic>{'ok': true}),
      ]);
      expect(await bridge.stopServer(), isTrue);
    });
  });

  group('RuntimeBridge — execInRootfs', () {
    test('stdout, stderr, dan exitCode terparse', () async {
      _mockBridge([
        (
          'execInRootfs',
          {
            'cmd': 'uname -a',
            'timeoutMs': 30000,
          },
          () => <String, dynamic>{
                'ok': true,
                'exitCode': 0,
                'stdout': 'Linux localhost',
                'stderr': '',
              }
        ),
      ]);
      final r = await bridge.execInRootfs('uname -a');
      expect(r.ok, isTrue);
      expect(r.exitCode, 0);
      expect(r.stdout, 'Linux localhost');
      expect(r.stderr, isEmpty);
    });

    test('perintah gagal exitCode 1 dengan stderr terisi', () async {
      _mockBridge([
        (
          'execInRootfs',
          {
            'cmd': 'ls /nonexistent',
            'timeoutMs': 1000,
          },
          () => <String, dynamic>{
                'ok': false,
                'exitCode': 1,
                'stdout': '',
                'stderr': 'ls: /nonexistent: No such file or directory',
              }
        ),
      ]);
      final r = await bridge.execInRootfs('ls /nonexistent', timeoutMs: 1000);
      expect(r.ok, isFalse);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('No such file'));
    });
  });

  group('RuntimeBridge — httpProxy', () {
    test('status dan body JSON proxy terbaca utuh', () async {
      _mockBridge([
        (
          'httpProxy',
          {
            'method': 'GET',
            'path': '/api/info',
            'headers': {'Accept': 'application/json'},
          },
          () => <String, dynamic>{
                'status': 200,
                'body': '{"version":"2.4.1"}',
              }
        ),
      ]);
      final r = await bridge.httpProxy(
        method: 'GET',
        path: '/api/info',
        headers: {'Accept': 'application/json'},
      );
      expect(r.status, 200);
      expect(r.body, '{"version":"2.4.1"}');
      expect(r.isOk, isTrue);
    });

    test('body JSON dengan header proxy + status non-2xx → isOk false',
        () async {
      _mockBridge([
        (
          'httpProxy',
          {
            'method': 'POST',
            'path': '/api/session/x/permission',
            'body': '{"allowed":false}',
            'headers': {'Content-Type': 'application/json'},
          },
          () => <String, dynamic>{'status': 500, 'body': 'down'}
        ),
      ]);
      final r = await bridge.httpProxy(
        method: 'POST',
        path: '/api/session/x/permission',
        body: '{"allowed":false}',
        headers: {'Content-Type': 'application/json'},
      );
      expect(r.status, 500);
      expect(r.isOk, isFalse);
    });
  });

  group('RuntimeBridge — event progress instalasi', () {
    test('stream progressEvents menerjemahkan event channel ke ProgressEvent',
        () async {
      // EventChannel `oagents/progress` dibungkus stream tiruan.
      final controller = StreamController<dynamic>.broadcast();
      final bridgeWithEvents = RuntimeBridge(
        eventChannel: _FakeEventChannel(controller.stream),
      );
      final received = <ProgressEvent>[];
      final sub = bridgeWithEvents.progressEvents().listen(received.add);
      controller.add(<String, dynamic>{
        'stage': 'downloading',
        'pct': 42,
        'detail': 'rootfs 12/28 MB',
      });
      controller.add(<String, dynamic>{'stage': 'ready', 'pct': 100});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(received, hasLength(2));
      expect(received[0].stage, RuntimeStage.downloading);
      expect(received[0].pct, 42);
      expect(received[0].detail, 'rootfs 12/28 MB');
      expect(received[1].stage, RuntimeStage.ready);
    });
  });
}

/// EventChannel tiruan yang mengalirkan stream Dart lokal tanpa native.
class _FakeEventChannel implements EventChannel {
  _FakeEventChannel(this._stream);
  final Stream<dynamic> _stream;

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) => _stream;

  @override
  String get name => 'oagents/progress';

  @override
  MethodCodec get codec => const StandardMethodCodec();

  @override
  BinaryMessenger get binaryMessenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  @override
  MethodCodec get codec => const StandardMethodCodec();
}
