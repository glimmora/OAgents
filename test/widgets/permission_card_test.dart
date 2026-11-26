// Uji widget PermissionCard — kartu izin tool inline (lihat file kembar:
// status_card_test.dart). Semua keputusan lewat callback, tanpa SnackBar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/models/chat_message.dart';
import 'package:oagents/widgets/permission_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

PermissionRequest _req({bool? decided}) => PermissionRequest(
      requestId: 'p-77',
      tool: 'write',
      summary: 'ubah lib/main.dart',
      sessionId: 's-9',
      decided: decided,
    );

void main() {
  testWidgets('klik Setuju mengirim (request, true) tepat sekali',
      (tester) async {
    final decisions = <(String, bool)>[];
    await tester.pumpWidget(_wrap(PermissionCard(
      request: _req(),
      onDecision: (r, a) => decisions.add((r.requestId, a)),
    )));
    await tester.tap(find.text('Setuju'));
    await tester.pump();
    expect(decisions, [('p-77', true)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('klik Tolak mengirim (request, false)', (tester) async {
    final decisions = <(String, bool)>[];
    await tester.pumpWidget(_wrap(PermissionCard(
      request: _req(),
      onDecision: (r, a) => decisions.add((r.requestId, a)),
    )));
    await tester.tap(find.text('Tolak'));
    await tester.pump();
    expect(decisions, [('p-77', false)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('kartu setelah diputuskan false menampilkan teks Ditolak',
      (tester) async {
    final r = _req(decided: false);
    await tester.pumpWidget(_wrap(PermissionCard(request: r)));
    expect(find.textContaining('Ditolak'), findsOneWidget);
    expect(find.text('Setuju'), findsNothing);
    expect(find.text('Tolak'), findsNothing);
  });

  testWidgets('SnackBar tidak pernah muncul walau di-tap berulang',
      (tester) async {
    var n = 0;
    await tester.pumpWidget(_wrap(PermissionCard(
      request: _req(),
      onDecision: (r, a) => n++,
    )));
    await tester.tap(find.text('Setuju'));
    await tester.pump();
    await tester.tap(find.text('Tolak'));
    await tester.pump();
    expect(n, 2);
    // Kontrak UI: tanpa SnackBar. (ScaffoldMessenger memang selalu ada
    // di MaterialApp — keberadaannya bukan berarti SnackBar tampil.)    expect(find.byType(SnackBar), findsNothing);
  });
}
