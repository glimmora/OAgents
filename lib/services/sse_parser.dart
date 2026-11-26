import 'dart:convert';

/// Parser SSE (Server-Sent Events) berbasis baris — murni Dart tanpa I/O
/// supaya dapat diuji unit sepenuhnya.
///
/// Aturan yang diikuti (lihat spesifikasi WHATWG SSE):
/// * `data: <teks>` menambah satu baris data; beberapa baris `data:` dalam
///   satu event disatukan dengan `\n` (reasembly multiline).
/// * `event: <nama>` menetapkan nama event; default `message`.
/// * `id: <id>` menetapkan id event terakhir (disertakan pada hasil).
/// * Baris kosong menutup event → emit satu `Map`.
/// * `:` di awal baris adalah komentar dan diabaikan.
/// * `retry:` diabaikan (tidak relevan untuk kanal proxy).
/// * CRLF dinormalisasi menjadi LF saat [push] memanggil [_feedLines].
class SseParser {
  /// Handler hasil — dipanggil setiap kali satu event lengkap terkumpul.
  final void Function(Map<String, dynamic> event) onEvent;

  SseParser(this.onEvent);

  final List<String> _dataLines = [];
  String? _lastEventId;
  String _eventType = 'message';

  /// Sisa baris parsial dari chunk sebelumnya — jaringan dapat memotong di
  /// tengah baris; baris baru diproses hanya bila terminatornya terlihat.
  String _pending = '';

  /// Memasukkan satu potongan teks mentah (boleh sebagian baris, karena
  /// jaringan dapat memotong di tengah baris) dan mengeluarkan event
  /// selesai yang terkandung di dalamnya.
  void push(String chunk) {
    final normalized = chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final combined = _pending + normalized;
    final lines = combined.split('\n');
    // Elemen terakhir belum tentu baris utuh: bila combined tidak diakhiri
    // terminator, elemen itu baris parsial — simpan untuk push berikutnya.
    _pending = lines.removeLast();
    for (final line in lines) {
      _handleLine(line);
    }
  }

  /// Memaksa event yang masih menumpuk keluar — dipanggil saat aliran tutup.
  void close() {
    if (_pending.isNotEmpty) {
      _handleLine(_pending);
      _pending = '';
    }
    if (_dataLines.isNotEmpty || _lastEventId != null) _emit();
  }

  /// State apakah ada event parsial yang menunggu baris kosong.
  bool get hasBufferedEvent =>
      _pending.isNotEmpty || _dataLines.isNotEmpty || _lastEventId != null;

  void _handleLine(String line) {
    if (line.isEmpty) {
      _emit();
      return;
    }
    if (line.startsWith(':')) return; // komentar SSE

    final colon = line.indexOf(':');
    String field;
    String value;
    if (colon < 0) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      // Spasi langsung setelah titik dua dipangkas. Spesifikasi SSE hanya
      // memangkas satu spasi, tetapi opencode menulis payload JSON dengan
      // indentasi; memangkas semua spasi awal aman untuk nilai field kami
      // (data/event/id) dan tidak menimpa spasi di tengah nilai.
      while (value.startsWith(' ')) {
        value = value.substring(1);
      }
    }

    switch (field) {
      case 'data':
        _dataLines.add(value);
        break;
      case 'event':
        _eventType = value.isEmpty ? 'message' : value;
        break;
      case 'id':
        if (!value.contains('\u0000')) _lastEventId = value;
        break;
      default:
        break; // retry dan field tak dikenal diabaikan
    }
  }

  void _emit() {
    if (_dataLines.isEmpty && _lastEventId == null) {
      // Baris kosong tanpa data apa pun — tidak mengirim event kosong.
      _eventType = 'message';
      return;
    }
    final data = _dataLines.join('\n');
    final event = <String, dynamic>{
      'event': _eventType,
      'data': data,
      if (_lastEventId != null) 'id': _lastEventId,
    };
    onEvent(event);
    _dataLines.clear();
    _eventType = 'message';
    _lastEventId = null;
  }
}

/// Membaca `data:` string SSE menjadi JSON bila valid; mengembalikan Map.
/// Mengembalikan `null` bila data kosong / bukan objek JSON.
Map<String, dynamic>? sseDataToJson(String? data) {
  if (data == null || data.isEmpty) return null;
  final trimmed = data.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

/// Membentuk Map event final dari hasil parser + decode JSON opsional.
Map<String, dynamic> sseEventToMap(Map<String, dynamic> event) {
  final data = event['data'];
  final decoded = data is String ? sseDataToJson(data) : null;
  if (decoded == null) {
    return {...event, 'json': null};
  }
  return {...event, 'json': decoded};
}
