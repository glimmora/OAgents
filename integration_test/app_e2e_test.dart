// E2E OAgents dengan bridge palsu — jalankan dengan:
//   flutter test integration_test --dart-define E2E_FAKE_BRIDGE=true
// FakeBridge meniru seluruh kanal `oagents/runtime` tanpa rootfs/proot
// nyata: rootfs terpasang, server siap, sesi "s1", prompt → teks "Halo"
// mengalir per 100 ms sebagai event SSE session.execution.partial.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:oagents/main.dart' as app;
import 'package:oagents/services/chat_controller.dart';
import 'package:oagents/services/opencode_client.dart';
import 'package:oagents/services/runtime_bridge.dart';

/// Versi konfigurasi uji: pakai FakeBridge bila E2E_FAKE_BRIDGE=true.
const _fakeMode = bool.fromEnvironment('E2E_FAKE_BRIDGE');

void main() {
  // flutter drive: extension wajib ter-registrasi SEBELUM binding lain
  // supaya VMServiceFlutterDriver.connect() → GetHealth berhasil.
  enableFlutterDriverExtension(handler: (data) async {
    // Driver meminta 'integration-test-done' setelah frame pertama; test
    // berjalan di app-isolate sendiri lewat IntegrationTest binding.
    return _fakeMode ? 'fake-bridge-ok' : 'real-bridge-ok';
  });
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (_fakeMode) {
      _installFakeNativeChannels();
    }
  });

  // Timeout eksplisit: default testWidgets 12 menit, sedangkan TCG (software
  // rendering tanpa KVM) jauh lebih lambat — build+install saja ~9 menit.
  testWidgets('e2e: pesan mengalir di tab Chat lalu kartu status tab Runtime',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // --- Tab Chat: kirim prompt pertama, sesi dibuat oleh fake ---
    await tester.enterText(find.byType(TextField), 'Halo');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Teks streaming "Halo" muncul sebagai balasan agent.
    expect(find.text('Halo'), findsAtLeast(1));
    // Tanpa SnackBar — semua umpan balik inline (kontrak UI).
    expect(find.byType(SnackBar), findsNothing);

    // --- Pindah tab Runtime ---
    await tester.tap(find.text('Runtime'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Kartu status runtime tampil (rootfs terpasang & server berjalan).
    expect(find.textContaining('Terpasang'), findsOneWidget);
    expect(find.textContaining('Berjalan di 127.0.0.1'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 40)));

  testWidgets('e2e: sesi "s1" tersambung dan daftar sesi menampilkan status',
      (tester) async {
    final controller =
        ChatController(client: OpencodeClient(bridge: RuntimeBridge()));
    expect(controller.sessionId, isNull); // controller baru tidak dipakai UI
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await tester.tap(find.text('Sesi'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(SnackBar), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 40)));
}

/// Mendaftarkan method-channel handler palsu + event progress statis.
void _installFakeNativeChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('oagents/runtime'), (
    MethodCall call,
  ) async {
    switch (call.method) {
      case 'rootfsStatus':
        return <String, dynamic>{
          'installed': true,
          'version': '2.4.1',
          'sizeMB': 78,
          'ok': true,
        };
      case 'serverStatus':
        return <String, dynamic>{
          'running': true,
          'pid': 4321,
          'port': 4096,
          'upMs': 9000,
        };
      case 'startServer':
        return <String, dynamic>{'ok': true, 'pid': 4321, 'port': 4096};
      case 'stopServer':
        return <String, dynamic>{'ok': true};
      case 'httpProxy':
        return _fakeHttp(call);
      case 'execInRootfs':
        return <String, dynamic>{
          'ok': true,
          'exitCode': 0,
          'stdout': '',
          'stderr': '',
        };
      default:
        return <String, dynamic>{'ok': false, 'error': 'belum ada di fake'};
    }
  });
}

dynamic _fakeHttp(MethodCall call) {
  final args = call.arguments as Map<Object?, Object?>? ?? const {};
  final path = args['path']?.toString() ?? '';
  if (path == '/api/info') {
    return <String, dynamic>{'status': 200, 'body': '{"version":"2.4.1"}'};
  }
  if (path == '/api/session' && args['method'] == 'POST') {
    return <String, dynamic>{
      'status': 200,
      'body': '{"sessionID":"s1"}',
    };
  }
  if (path.startsWith('/api/session/s1/prompt')) {
    return <String, dynamic>{'status': 200, 'body': '{"infoID":"i1"}'};
  }
  if (path.startsWith('/api/session/s1/wait')) {
    return <String, dynamic>{'status': 204, 'body': ''};
  }
  if (path.contains('/log')) {
    // SSE: teks "Halo" dikirim bertahap (dipicu timer cepat 100 ms).
    final sse = 'event: session.execution.partial\ndata: {"delta":"Halo"}\n\n';
    return <String, dynamic>{'status': 200, 'body': sse};
  }
  if (path == '/api/session') {
    return <String, dynamic>{
      'status': 200,
      'body': '[{"id":"s1","title":"Sesi pertama","updatedAt":1730000000000}]',
    };
  }
  if (path.startsWith('/api/session/s1/message')) {
    return <String, dynamic>{
      'status': 200,
      'body': '[{"role":"user","text":"Halo","time":1730000000000}]',
    };
  }
  if (path == '/api/model') {
    return <String, dynamic>{
      'status': 200,
      'body': '{"models":[{"id":"claude-sonnet"}]}',
    };
  }
  if (path == '/api/agent') {
    return <String, dynamic>{
      'status': 200,
      'body': '{"agents":[{"name":"build"},{"name":"plan"}]}',
    };
  }
  return <String, dynamic>{'status': 404, 'body': 'tidak ada di fake'};
}
