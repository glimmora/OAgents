// Uji unit model ChatMessage + ToolCallView + PermissionRequest —
// pabrik, copyWith, dan kesetaraan (lihat lib/models/chat_message.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/models/chat_message.dart';

void main() {
  group('ChatMessage — konstruksi & copyWith', () {
    test('pesan user dasar tersimpan utuh', () {
      final m = ChatMessage(
        role: ChatRole.user,
        text: 'Halo agent',
        timestamp: DateTime(2026, 11, 25, 10),
      );
      expect(m.role, ChatRole.user);
      expect(m.text, 'Halo agent');
      expect(m.pending, isFalse);
      expect(m.streamed, isFalse);
      expect(m.error, isFalse);
      expect(m.toolCalls, isEmpty);
      expect(m.permissionRequest, isNull);
    });

    test('copyWith mengubah teks tanpa mengubah role & timestamp', () {
      final t = DateTime(2026, 11, 25, 10);
      final m = ChatMessage(role: ChatRole.assistant, text: 'Ha', timestamp: t)
          .copyWith(text: 'Halo dunia');
      expect(m.text, 'Halo dunia');
      expect(m.role, ChatRole.assistant);
      expect(m.timestamp, t);
    });

    test('copyWith menandai pending selesai & streamed untuk streaming SSE',
        () {
      final m = ChatMessage(
        role: ChatRole.assistant,
        text: '',
        timestamp: DateTime.now(),
      ).copyWith(pending: true, streamed: true);
      expect(m.pending, isTrue);
      expect(m.streamed, isTrue);
      final done = m.copyWith(pending: false);
      expect(done.pending, isFalse);
      expect(done.streamed, isTrue); // streamed tidak ikut berubah
    });

    test('copyWith menambah toolCalls ke pesan assistant', () {
      final m = ChatMessage(
        role: ChatRole.assistant,
        text: 'kerja',
        timestamp: DateTime.now(),
      ).copyWith(
        toolCalls: [const ToolCallView(tool: 'bash', input: 'ls -la')],
      );
      expect(m.toolCalls, hasLength(1));
      expect(m.toolCalls.single.tool, 'bash');
      expect(m.toolCalls.single.running, isTrue);
      expect(m.toolCalls.single.output, isNull);
    });
  });

  group('ChatMessage — galat sebagai kartu status', () {
    test('pesan sistem bertanda error untuk kartu galat inline', () {
      final m = ChatMessage(
        role: ChatRole.system,
        text: 'Gagal kirim — server mati',
        timestamp: DateTime.now(),
        error: true,
      );
      expect(m.role, ChatRole.system);
      expect(m.error, isTrue);
    });
  });

  group('PermissionRequest — keputusan & kesetaraan', () {
    test('decided null default; copy ber-decided true lewat konstruktor', () {
      final r = PermissionRequest(
        requestId: 'r-1',
        tool: 'bash',
        summary: 'rm -rf /tmp/x',
        sessionId: 's-1',
      );
      expect(r.decided, isNull);
      final r2 = PermissionRequest(
        requestId: r.requestId,
        tool: r.tool,
        summary: r.summary,
        sessionId: r.sessionId,
        decided: true,
      );
      expect(r2.decided, isTrue);
      expect(r2, equals(r)); // kesetaraan tetap berbasis requestId
    });

    test('kesetaraan berdasar requestId (dua objek berbeda tetap ==)', () {
      final a = PermissionRequest(
        requestId: 'r-9',
        tool: 'bash',
        summary: 'a',
        sessionId: 's',
      );
      final b = PermissionRequest(
        requestId: 'r-9',
        tool: 'write',
        summary: 'b',
        sessionId: 's',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ToolCallView — state berjalan & selesai', () {
    test('tool selesai membawa output dan running false', () {
      final c = const ToolCallView(
        tool: 'bash',
        input: 'echo hi',
        running: false,
        output: 'hi',
      );
      expect(c.running, isFalse);
      expect(c.output, 'hi');
    });
  });

  group('ChatRole — seluruh nilai enum', () {
    test('tiga peran pengirim terdefinisi', () {
      expect(ChatRole.values,
          containsAll([ChatRole.user, ChatRole.assistant, ChatRole.system]));
    });
  });
}
