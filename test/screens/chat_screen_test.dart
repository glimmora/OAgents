// Uji widget ChatScreen — daftar pesan, input aktif, kirim → ChatController,
// dan kartu StatusCard inline (tanpa SnackBar). Controller asli
// ChatController disubclass fake agar server tak tersentuh.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/models/chat_message.dart';
import 'package:oagents/screens/chat_screen.dart';
import 'package:oagents/services/chat_controller.dart';
import 'package:oagents/services/opencode_client.dart';
import 'package:oagents/services/runtime_bridge.dart';
import 'package:oagents/widgets/status_card.dart';
import 'package:provider/provider.dart';

/// Bridge dummy — tidak pernah dipanggil karena semua metode controller
/// yang dipakai layar sudah di-override oleh [_FakeController].
class _DummyBridge extends RuntimeBridge {
  @override
  Future<ProxyResponse> httpProxy({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    String? body,
  }) async =>
      const ProxyResponse(status: 500, body: '{}');
}

/// Fake ChatController: meng-override antarmuka yang dibaca ChatScreen
/// (messages, sessionId, sending, sendPrompt, decidePermission).
/// Client dibangun dari bridge dummy yang selalu membalas 500 — tidak
/// pernah benar-benar dipakai karena semua metode teroverride.
class _FakeController extends ChatController {
  _FakeController()
      : super(
          client: OpencodeClient(
            bridge: _DummyBridge(),
          ),
        );

  final List<ChatMessage> _msgs = <ChatMessage>[];
  String? _sessionId;
  final bool _sending = false;
  int sendCalls = 0;
  final List<(String, bool)> decisions = <(String, bool)>[];

  @override
  List<ChatMessage> get messages => List.unmodifiable(_msgs);

  @override
  String? get sessionId => _sessionId;

  @override
  bool get sending => _sending;

  @override
  void seed(ChatMessage m) {
    _msgs.add(m);
    notifyListeners();
  }

  @override
  Future<void> sendPrompt(String text) async {
    sendCalls++;
    _msgs.add(ChatMessage(
      role: ChatRole.user,
      text: text,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  @override
  Future<void> decidePermission(PermissionRequest request, bool allowed) async {
    decisions.add((request.requestId, allowed));
  }
}

Widget _app(_FakeController c) => ChangeNotifierProvider<ChatController>.value(
      value: c,
      child: const MaterialApp(home: ChatScreen()),
    );

void main() {
  late _FakeController controller;

  setUp(() {
    controller = _FakeController();
  });

  testWidgets('daftar pesan terrender: user, assistant, sistem',
      (tester) async {
    controller
      ..seed(ChatMessage(
          role: ChatRole.user, text: 'Halo', timestamp: DateTime.now()))
      ..seed(ChatMessage(
          role: ChatRole.assistant,
          text: 'Hai, apa kabar?',
          timestamp: DateTime.now()))
      ..seed(ChatMessage(
          role: ChatRole.system,
          text: 'Sesi baru dibuat',
          timestamp: DateTime.now()));
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(find.text('Halo'), findsOneWidget);
    expect(find.text('Hai, apa kabar?'), findsOneWidget);
    expect(find.text('Sesi baru dibuat'), findsOneWidget);
  });

  testWidgets('input teks aktif dan bisa diketik', (tester) async {
    await tester.pumpWidget(_app(controller));
    await tester.enterText(find.byType(TextField), 'pesan percobaan');
    await tester.pump();
    expect(find.widgetWithText(TextField, 'pesan percobaan'), findsOneWidget);
<<<<<<< HEAD
    // enabled null berarti aktif secara default (bukan disabled).
    expect(
        tester.widget<TextField>(find.byType(TextField)).enabled, isNot(false));
=======
    // enabled == null berarti mengikuti default (aktif); hanya false yang
    // berarti nonaktif.
    expect(tester.widget<TextField>(find.byType(TextField)).enabled,
        isNot(equals(false)));
>>>>>>> fe667b1 (Perbaikan build rilis: signing keystore, split-per-ABI, ikon, R8, SseParser, 97 test hijau)
  });

  testWidgets('tekan tombol kirim memanggil sendPrompt controller',
      (tester) async {
    await tester.pumpWidget(_app(controller));
    await tester.enterText(find.byType(TextField), 'halo agent');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(controller.sendCalls, 1);
    expect(find.text('halo agent'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('pesan pending tanpa teks menampilkan indikator berpikir',
      (tester) async {
    controller.seed(ChatMessage(
      role: ChatRole.assistant,
      text: '',
      pending: true,
      timestamp: DateTime.now(),
    ));
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(find.textContaining('agent sedang berpikir'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('StatusCard inline muncul untuk pesan sistem (tanpa SnackBar)',
      (tester) async {
    controller.seed(ChatMessage(
      role: ChatRole.system,
      text: 'Server opencode berjalan',
      timestamp: DateTime.now(),
    ));
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is StatusCard), findsOneWidget);
    expect(find.text('Server opencode berjalan'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'StatusCard muncul saat proses (pesan sistem pending = tahap berjalan)',
      (tester) async {
    controller.seed(ChatMessage(
      role: ChatRole.system,
      text: 'Mengunduh rootfs',
      pending: true,
      timestamp: DateTime.now(),
    ));
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is StatusCard), findsOneWidget);
    expect(find.text('sedang berjalan…'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
