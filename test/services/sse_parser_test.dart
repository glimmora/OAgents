// Uji unit SseParser — parser SSE murni Dart (lihat docs/OPENCODE_CLIENT_CONTRACT.md).
// Semua parsing dites tanpa I/O jaringan: input berupa string mentah SSE.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/services/sse_parser.dart';

/// Helper: menjalankan stream potongan (seolah data diterima bertahap dari
/// `httpProxy`) melewati satu [SseParser], lalu memanggil [SseParser.close].
Future<List<Map<String, dynamic>>> pumpStream(List<String> chunks) async {
  final events = <Map<String, dynamic>>[];
  final parser = SseParser(events.add);
  await for (final chunk in Stream<String>.fromIterable(chunks)) {
    parser.push(chunk);
  }
  parser.close();
  return events;
}

void main() {
  group('SseParser — parsing dasar event/data/id', () {
    test('satu event lengkap: event, data, dan id terbaca', () async {
      final out = await pumpStream([
        'event: session.execution.started\n',
        'id: 7\n',
        'data: {"seq":7}\n',
        '\n',
      ]);
      expect(out, hasLength(1));
      expect(out.single['event'], 'session.execution.started');
      expect(out.single['data'], '{"seq":7}');
      expect(out.single['id'], '7');
    });

    test('event tanpa nama memakai default "message"', () async {
      final out = await pumpStream(['data: halo\n', '\n']);
      expect(out.single['event'], 'message');
      expect(out.single['data'], 'halo');
    });

    test('beberapa baris data disatukan dengan newline (reasembly)', () async {
      final out = await pumpStream([
        'data: baris pertama\n',
        'data: baris kedua\n',
        'data: baris ketiga\n',
        '\n',
      ]);
      expect(out.single['data'], 'baris pertama\nbaris kedua\nbaris ketiga');
    });

    test('baris komentar (awalan ":") diabaikan sepenuhnya', () async {
      final out = await pumpStream([
        ': ini komentar keep-alive\n',
        'data: ok\n',
        ': komentar lain\n',
        '\n',
      ]);
      expect(out, hasLength(1));
      expect(out.single['data'], 'ok');
    });

    test('field "retry" dan field tak dikenal diabaikan', () async {
      final out = await pumpStream([
        'retry: 5000\n',
        'heartbeat: apapun\n',
        'data: tetap\n',
        '\n',
      ]);
      expect(out, hasLength(1));
      expect(out.single['data'], 'tetap');
    });
  });

  group('SseParser — normalisasi baris', () {
    test('CRLF (\\r\\n) dinormalisasi dan event tetap terbaca', () async {
      final out = await pumpStream([
        'event: ping\r\n',
        'data: dari windows\r\n',
        '\r\n',
      ]);
      expect(out, hasLength(1));
      expect(out.single['event'], 'ping');
      expect(out.single['data'], 'dari windows');
    });

    test('CR telanjang (\\r) juga dianggap pemisah baris', () async {
      final out = await pumpStream(['data: satu\r', 'data: dua\r', '\r']);
      expect(out.single['data'], 'satu\ndua');
    });

    test('spasi setelah titik dua dipangkas dari nilai field', () async {
      final out = await pumpStream(['data:   berjarak\n', '\n']);
      expect(out.single['data'], 'berjarak');
    });

    test('baris field tanpa titik dua diperlakukan field kosong nilainya', () async {
      final out = await pumpStream(['data\n', '\n']);
      expect(out.single['data'], '');
    });
  });

  group('SseParser — perilaku emit & buffer', () {
    test('event tanpa baris data tidak menghasilkan keluaran', () async {
      final out = await pumpStream(['event: noop\n', '\n']);
      expect(out, isEmpty);
    });

    test('chunk kosong dan baris kosong beruntun tidak memicu event', () async {
      final out = await pumpStream(['', '\n', '\n', '']);
      expect(out, isEmpty);
    });

    test('event parsial tanpa baris kosong keluar saat close()', () {
      final events = <Map<String, dynamic>>[];
      final parser = SseParser(events.add);
      parser.push('data: terpotong\n');
      expect(parser.hasBufferedEvent, isTrue);
      parser.close();
      expect(events, hasLength(1));
      expect(events.single['data'], 'terpotong');
    });

    test('potongan terpisah antar push (koneksi terputus) tetap utuh', () {
      final events = <Map<String, dynamic>>[];
      final parser = SseParser(events.add);
      parser.push('event: session.execution.pa');
      parser.push('rtial\nid: 11\nda');
      parser.push('ta: {"delta":"Ha"}\n');
      parser.push('\n');
      expect(events, hasLength(1));
      expect(events.single['event'], 'session.execution.partial');
      expect(events.single['id'], '11');
      expect(events.single['data'], '{"delta":"Ha"}');
    });

    test('dispatch ganda: dua event berturut-turut terpisah rapi', () async {
      final out = await pumpStream([
        'event: a\n',
        'data: satu\n',
        '\n',
        'event: b\n',
        'data: dua\n',
        '\n',
      ]);
      expect(out.map((e) => e['data']), ['satu', 'dua']);
      expect(out.map((e) => e['event']), ['a', 'b']);
    });
  });

  group('SseParser — skenario opencode nyata', () {
    test('id numerik besar tetap string utuh (tanpa konversi int)', () async {
      final out = await pumpStream(['id: 18446744073709551615\n', 'data: x\n', '\n']);
      expect(out.single['id'], '18446744073709551615');
      expect(out.single['id'], isA<String>());
    });

    test('event "session.execution.partial" dengan delta teks', () async {
      final out = await pumpStream([
        'event: session.execution.partial\n',
        'data: {"delta":"Halo dunia"}\n',
        '\n',
      ]);
      final map = sseEventToMap(out.single);
      expect(map['event'], 'session.execution.partial');
      expect(map['json'], isNotNull);
      expect(map['json']['delta'], 'Halo dunia');
    });

    test('payload besar: 1000 event diparse tanpa kebocoran state', () async {
      final chunks = List<String>.generate(1000, (i) {
        return 'event: session.execution.partial\nid: $i\ndata: {"seq":$i}\n\n';
      });
      final out = await pumpStream(chunks);
      expect(out, hasLength(1000));
      // Event pertama & terakhir benar — urutan tidak bergeser.
      expect(out.first['json'] == null ? out.first['data'] : '',
          startsWith('{"seq":0}'));
      expect(out.last['id'], '999');
      expect(out.last['event'], 'session.execution.partial');
      // Antar event, state (event/data/id) ter-reset.
      expect(out[500]['id'], '500');
      expect(out[500]['data'], '{"seq":500}');
    });

    test('sseDataToJson mengembalikan null untuk data non-objek', () {
      expect(sseDataToJson(null), isNull);
      expect(sseDataToJson(''), isNull);
      expect(sseDataToJson('teks polos'), isNull);
      expect(sseDataToJson('["bukan objek"]'), isNull);
      expect(sseDataToJson('json rusak bukan objek'), isNull);
      expect(sseDataToJson('{"ok":true}'), {'ok': true});
    });

    test('sseEventToMap menempelkan "json": null bila data bukan JSON objek', () {
      final map = sseEventToMap({'event': 'x', 'data': 'plain'});
      expect(map['json'], isNull);
      expect(map['event'], 'x');
    });

    test('id berisi karakter NOL (\\u0000) ditolak spesifikasi SSE', () async {
      final out = await pumpStream([
        'id: b\u0000ad\n',
        'data: tetap terbaca\n',
        '\n',
      ]);
      // id mengandung NUL → diabaikan; data tetap terkirim sebagai event.
      expect(out, hasLength(1));
      expect(out.single.containsKey('id'), isFalse);
      expect(out.single['data'], 'tetap terbaca');
    });
  });
}
