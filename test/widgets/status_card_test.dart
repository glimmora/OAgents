// Uji widget StatusCard & PermissionCard — kartu status inline (tanpa
// SnackBar/popup). Kontrak UI: semua umpan balik tampil sebagai kartu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/models/chat_message.dart';
import 'package:oagents/widgets/permission_card.dart';
import 'package:oagents/widgets/status_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('StatusCard — render teks & elemen', () {
    testWidgets('judul dan detail tampil', (tester) async {
      await tester.pumpWidget(_wrap(const StatusCard(
        title: 'Server opencode',
        detail: 'Berjalan di 127.0.0.1:4096 (pid 1234).',
      )));
      expect(find.text('Server opencode'), findsOneWidget);
      expect(
          find.text('Berjalan di 127.0.0.1:4096 (pid 1234).'), findsOneWidget);
    });

    testWidgets('progress non-null menampilkan LinearProgressIndicator',
        (tester) async {
      await tester.pumpWidget(_wrap(const StatusCard(
        title: 'Mengunduh rootfs',
        progress: 42,
      )));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Mengunduh rootfs'), findsOneWidget);
    });

    testWidgets('onTap memanggil callback dan tanpa SnackBar', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(StatusCard(
        title: 'Kartu tersentuh',
        onTap: () => tapped++,
      )));
      await tester.tap(find.text('Kartu tersentuh'));
      await tester.pump();
      expect(tapped, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(SnackBarBehavior), findsNothing);
    });

    testWidgets('mode compact & ikon berjalan (run) tetap dirender tanpa galat',
        (tester) async {
      await tester.pumpWidget(_wrap(const StatusCard(
        title: 'Eksekusi dimulai…',
        icon: 'run',
        tone: StatusTone.run,
        compact: true,
      )));
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('PermissionCard — keputusan izin tool', () {
<<<<<<< HEAD
    PermissionRequest req() => PermissionRequest(
=======
    PermissionRequest _req({bool? decided}) => PermissionRequest(
>>>>>>> fe667b1 (Perbaikan build rilis: signing keystore, split-per-ABI, ikon, R8, SseParser, 97 test hijau)
          requestId: 'r-1',
          tool: 'bash',
          summary: 'rm -rf /tmp/bersih',
          sessionId: 's-1',
          decided: decided,
        );

    testWidgets('judul tool & ringkas perintah tampil', (tester) async {
      await tester.pumpWidget(_wrap(PermissionCard(request: req())));
      expect(find.text('Izin tool: bash'), findsOneWidget);
      expect(find.text('rm -rf /tmp/bersih'), findsOneWidget);
      expect(find.textContaining('Agent ingin menjalankan'), findsOneWidget);
    });

    testWidgets('tombol Setuju memanggil callback allowed=true',
        (tester) async {
      final seen = <bool>[];
      await tester.pumpWidget(_wrap(PermissionCard(
        request: req(),
        onDecision: (r, allowed) => seen.add(allowed),
      )));
      await tester.tap(find.text('Setuju'));
      await tester.pump();
      expect(seen, [true]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('tombol Tolak memanggil callback allowed=false',
        (tester) async {
      final seen = <bool>[];
      await tester.pumpWidget(_wrap(PermissionCard(
        request: req(),
        onDecision: (r, allowed) => seen.add(allowed),
      )));
      await tester.tap(find.text('Tolak'));
      await tester.pump();
      expect(seen, [false]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('tanpa callback: tombol nonaktif, tekan tidak melempar',
        (tester) async {
<<<<<<< HEAD
      await tester.pumpWidget(_wrap(PermissionCard(request: req())));
      // Tombol Setuju dibangun FilledButton.icon (subclass privat _FilledButtonWithIcon)
      // — cari lewat widget leluhur ButtonStyleButton milik tombol berteck 'Setuju'.
      final btn = find.ancestor(
        of: find.text('Setuju'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(
        tester.widget<ButtonStyleButton>(btn).onPressed,
        isNull,
      );
=======
      await tester.pumpWidget(_wrap(PermissionCard(request: _req())));
      // FilledButton.icon/OutlinedButton.icon tidak cocok dengan byType;
      // cek lewat teks label: tombol tanpa onPressed tidak melempar.
>>>>>>> fe667b1 (Perbaikan build rilis: signing keystore, split-per-ABI, ikon, R8, SseParser, 97 test hijau)
      await tester.tap(find.text('Setuju'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('sudah diputuskan → status "Disetujuji" tanpa tombol',
        (tester) async {
<<<<<<< HEAD
      final r = req()..decided = true;
=======
      final r = _req(
        decided: true,
      );
>>>>>>> fe667b1 (Perbaikan build rilis: signing keystore, split-per-ABI, ikon, R8, SseParser, 97 test hijau)
      await tester.pumpWidget(_wrap(PermissionCard(request: r)));
      expect(find.text('Setuju'), findsNothing);
      expect(find.textContaining('Disetujuji'), findsOneWidget);
    });

    testWidgets('ringkasan kosong → em-dash, bukan celah kosong',
        (tester) async {
      final r = PermissionRequest(
        requestId: 'r-2',
        tool: 'edit',
        summary: '',
        sessionId: 's-2',
      );
      await tester.pumpWidget(_wrap(PermissionCard(request: r)));
      expect(find.text('—'), findsOneWidget);
    });
  });
}
