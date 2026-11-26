import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:oagents/models/api_result.dart';
import 'package:oagents/models/chat_message.dart';
import 'package:oagents/services/opencode_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengendali percakapan: kirim prompt → streaming SSE → teks partial
/// ditambahkan ke [ChatMessage] aktif secara real-time; panggilan tool &
/// permintaan izin tampil sebagai kartu inline yang diputuskan pengguna.
///
/// Semua umpan balik (termasuk galat) masuk daftar pesan sebagai kartu
/// status — TIDAK ADA popup notifikasi.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.client,
    SharedPreferences? prefs,
  }) : _prefs = prefs;

  final OpencodeClient client;
  SharedPreferences? _prefs;

  static const String _lastSessionKey = 'oagents.lastSession';

  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<PermissionRequest> _permissions = <PermissionRequest>[];

  /// Log bootstrap runtime untuk kartu log (baris teks + tahap).
  final List<String> _bootstrapLog = <String>[];

  String? _sessionId;
  bool _sending = false;
  bool _following = false;
  StreamSubscription<Map<String, dynamic>>? _logSub;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<PermissionRequest> get permissions => List.unmodifiable(_permissions);
  String? get sessionId => _sessionId;
  bool get sending => _sending;
  bool get ready => _sessionId != null;
  List<String> get bootstrapLog => List.unmodifiable(_bootstrapLog);

  /// Menyiapkan `shared_preferences` (dipanggil sekali saat aplikasi mulai).
  Future<void> ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Menyetor instance prefs yang sudah dibuat oleh FutureProvider di main.
  Future<void> ensurePrefsLoaded(SharedPreferences prefs) async {
    _prefs ??= prefs;
  }

  // ---------------------------------------------------------- sesi

  /// Memuat sesi terakhir dari penyimpanan lokal; `null` bila belum ada.
  Future<String?> loadLastSession() async {
    await ensurePrefs();
    final id = _prefs?.getString(_lastSessionKey);
    if (id == null || id.isEmpty) return null;
    _sessionId = id;
    notifyListeners();
    return id;
  }

  Future<void> _saveLastSession(String id) async {
    await ensurePrefs();
    await _prefs?.setString(_lastSessionKey, id);
  }

  /// Membuat sesi baru bila belum ada; menampilkan kartu galat bila gagal.
  Future<void> ensureSession() async {
    if (_sessionId != null) return;
    final res = await client.createSession();
    switch (res) {
      case ApiOk(value: final id):
        _sessionId = id;
        await _saveLastSession(id);
        _addStatus('Sesi baru dibuat: $id', icon: 'ok');
      case ApiErr(:final message):
        _addStatus(
          'Gagal membuat sesi — $message. Pastikan server opencode '
          'berjalan di tab Runtime.',
          error: true,
        );
    }
    notifyListeners();
  }

  /// Membuka sesi yang sudah ada: muat pesan lalu ikuti log SSE.
  Future<void> openSession(String id, {String? title}) async {
    await stopFollowing();
    _sessionId = id;
    await _saveLastSession(id);
    _messages.clear();
    _permissions.clear();
    _addStatus(
      'Membuka sesi ${title ?? id}…',
      icon: 'info',
    );
    notifyListeners();
    final res = await client.getMessages(id);
    switch (res) {
      case ApiOk(value: final list):
        if (list.isEmpty) {
          _addStatus('Sesi ini belum memiliki pesan.', icon: 'info');
        }
        for (final raw in list) {
          _appendHistoryMessage(raw);
        }
      case ApiErr(:final message):
        _addStatus('Gagal memuat pesan sesi — $message', error: true);
    }
    _addStatus('Percakapan dimuat. Ketik pesan untuk melanjutkan.', icon: 'ok');
    notifyListeners();
    _startLogFollow();
  }

  /// Mengubah pesan riwayat JSON mentah menjadi [ChatMessage] di daftar.
  void _appendHistoryMessage(Map<String, dynamic> raw) {
    final roleStr = (raw['role'] ?? raw['type'] ?? '').toString();
    final role = switch (roleStr.toLowerCase()) {
      'user' => ChatRole.user,
      'assistant' || 'agent' => ChatRole.assistant,
      _ => ChatRole.system,
    };
    final text = _textOf(raw);
    _messages.add(
      ChatMessage(role: role, text: text, timestamp: _timeOf(raw)),
    );
  }

  static String _textOf(Map<String, dynamic> raw) {
    final Object? any = raw['text'] ?? raw['content'] ?? raw['body'];
    if (any is String) return any;
    if (any is List) {
      final parts = <String>[];
      for (final part in any) {
        if (part is Map) {
          final t = part['text'] ?? part['content'];
          if (t is String) parts.add(t);
        } else if (part is String) {
          parts.add(part);
        }
      }
      return parts.join('\n');
    }
    return '';
  }

  static DateTime _timeOf(Map<String, dynamic> raw) {
    final t = raw['time'] ?? raw['createdAt'] ?? raw['created'];
    if (t is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        t > 1000000000000 ? t : t * 1000,
      );
    }
    if (t is String) {
      final parsed = DateTime.tryParse(t);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  // ---------------------------------------------------------- kirim

  /// Mengirim prompt pengguna, lalu men-stream balasan SSE.
  Future<void> sendPrompt(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    await ensureSession();
    final sessionId = _sessionId;
    if (sessionId == null) return;

    _messages.add(
      ChatMessage(
          role: ChatRole.user, text: trimmed, timestamp: DateTime.now()),
    );
    _sending = true;
    notifyListeners();

    final res = await client.sendPrompt(sessionId, trimmed);
    switch (res) {
      case ApiOk():
        _startLogFollow();
      case ApiErr(:final message):
        _addStatus(
          'Gagal mengirim prompt — $message. Cek server di tab Runtime.',
          error: true,
        );
    }
    _sending = false;
    notifyListeners();
    // Tunggu eksekusi selesai supaya indikator pending akurat.
    unawaited(_awaitCompletion(sessionId));
  }

  Future<void> _awaitCompletion(String sessionId) async {
    final res = await client.waitForSession(sessionId);
    switch (res) {
      case ApiOk():
        break;
      case ApiErr(:final message):
        _addStatus('Sesi selesai dengan galat: $message', error: true);
    }
    _markPendingDone();
  }

  void _markPendingDone() {
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.pending) {
        _messages[i] = m.copyWith(pending: false);
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------- log SSE

  void _startLogFollow() {
    final sessionId = _sessionId;
    if (sessionId == null || _following) return;
    _following = true;
    _logSub = client.followLog(sessionId).listen(
      _onLogEvent,
      onError: (Object e) {
        _following = false;
        _addStatus('Aliran log terhenti: $e', error: true);
        notifyListeners();
      },
      onDone: () {
        _following = false;
      },
    );
  }

  Future<void> stopFollowing() async {
    await _logSub?.cancel();
    _logSub = null;
    _following = false;
  }

  /// Event SSE → pembaruan pesan aktif / panggilan tool / permintaan izin.
  void _onLogEvent(Map<String, dynamic> event) {
    final name = (event['event'] ?? '').toString();
    final json = event['json'];
    final payload =
        json is Map<String, dynamic> ? json : const <String, dynamic>{};

    if (name.startsWith('session.execution')) {
      _handleExecutionEvent(name, payload);
      notifyListeners();
      return;
    }
    if (name.contains('permission') || _looksLikePermission(payload)) {
      _handlePermissionEvent(payload);
      notifyListeners();
      return;
    }
    if (name.contains('tool') || _looksLikeToolCall(payload)) {
      _handleToolEvent(payload);
      notifyListeners();
      return;
    }
    // Event teks parsial — streaming real-time ke pesan assistant aktif.
    final partial = _partialText(payload);
    if (partial != null && partial.isNotEmpty) {
      _appendPartial(partial);
      notifyListeners();
      return;
    }
    final info = _detailOf(payload);
    if (info.isNotEmpty) {
      _bootstrapLogAdd('[$name] $info');
    }
  }

  void _handleExecutionEvent(String name, Map<String, dynamic> payload) {
    final part = name.split('.').last; // started/ended/idle…
    switch (part) {
      case 'started':
        _addStatus('Eksekusi dimulai…', icon: 'run', pending: true);
        break;
      case 'ended' || 'completed' || 'idle' || 'finished':
        _markPendingDone();
        _bootstrapLogAdd('Eksekusi selesai.');
        break;
      default:
        _bootstrapLogAdd('[$name] ${_detailOf(payload)}');
    }
  }

  void _handlePermissionEvent(Map<String, dynamic> payload) {
    final id =
        (payload['requestID'] ?? payload['requestId'] ?? payload['id'] ?? '')
            .toString();
    if (id.isEmpty || _permissions.any((p) => p.requestId == id)) return;
    final tool = (payload['tool'] ?? payload['name'] ?? 'tool').toString();
    final summary = _summarizeCommand(payload);
    final sessionId = _sessionId ?? '';
    final request = PermissionRequest(
      requestId: id,
      tool: tool,
      summary: summary,
      sessionId: sessionId,
    );
    _permissions.add(request);
    // Kartu izin juga muncul di daftar pesan supaya konteksnya terlihat.
    _messages.add(
      ChatMessage(
        role: ChatRole.assistant,
        text: 'Meminta izin menjalankan `$tool`',
        permissionRequest: request,
        timestamp: DateTime.now(),
      ),
    );
  }

  bool _looksLikePermission(Map<String, dynamic> payload) {
    final keys = payload.keys.toSet();
    return keys.contains('permissionID') ||
        keys.contains('permission') ||
        (payload['type']?.toString().contains('permission') ?? false);
  }

  void _handleToolEvent(Map<String, dynamic> payload) {
    final active = _activeAssistantIndex();
    final tool = (payload['tool'] ?? payload['name'] ?? payload['type'] ?? '')
        .toString();
    final input = _summarizeCommand(payload);
    final state = payload['state']?.toString().toLowerCase() ?? 'running';
    if (tool.isEmpty) return;
    if (active < 0) {
      // Tidak ada pesan streaming aktif — buat pesan assistant baru.
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          text: '',
          streamed: true,
          pending: true,
          toolCalls: [
            ToolCallView(tool: tool, input: input, running: state == 'running'),
          ],
          timestamp: DateTime.now(),
        ),
      );
      return;
    }
    final msg = _messages[active];
    final calls = [...msg.toolCalls];
    final idx = calls.indexWhere(
      (c) => c.tool == tool && c.input == input,
    );
    if (idx >= 0) {
      calls[idx] = ToolCallView(
        tool: tool,
        input: input,
        running: state == 'running',
        output: payload['output']?.toString(),
      );
    } else {
      calls.add(
        ToolCallView(
          tool: tool,
          input: input,
          running: state == 'running',
          output: payload['output']?.toString(),
        ),
      );
    }
    _messages[active] = msg.copyWith(toolCalls: calls);
  }

  bool _looksLikeToolCall(Map<String, dynamic> payload) {
    final type = payload['type']?.toString().toLowerCase() ?? '';
    return type.contains('tool') || payload.containsKey('toolCall');
  }

  /// Indeks pesan assistant terakhir yang sedang streaming/pending.
  int _activeAssistantIndex() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == ChatRole.assistant && (m.pending || m.streamed)) {
        return i;
      }
    }
    return -1;
  }

  void _appendPartial(String partial) {
    final idx = _activeAssistantIndex();
    if (idx < 0) {
      _messages.add(
        ChatMessage(
          role: ChatRole.assistant,
          text: partial,
          streamed: true,
          pending: true,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }
    final msg = _messages[idx];
    _messages[idx] = msg.copyWith(text: msg.text + partial);
  }

  String? _partialText(Map<String, dynamic> payload) {
    for (final key in const ['text', 'delta', 'partial', 'content']) {
      final v = payload[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static String _detailOf(Map<String, dynamic> payload) {
    for (final key in const ['detail', 'message', 'status', 'info']) {
      final v = payload[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  /// Ringkasan perintah tool: bash → perintahnya, write/edit → target berkas.
  String _summarizeCommand(Map<String, dynamic> payload) {
    final input = payload['input'] ?? payload['args'] ?? payload['command'];
    if (input is String && input.isNotEmpty) {
      return _shorten(input);
    }
    if (input is Map) {
      for (final key in const ['command', 'cmd', 'file', 'path', 'url']) {
        final v = input[key];
        if (v is String && v.isNotEmpty) return _shorten(v);
      }
      return _shorten(input.toString());
    }
    return _shorten(payload.toString());
  }

  static String _shorten(String s) {
    final t = s.trim().replaceAll('\n', ' ');
    if (t.length <= 120) return t;
    return '${t.substring(0, 117)}…';
  }

  // ---------------------------------------------------------- izin

  /// Keputusan pengguna dari kartu izin inline.
  Future<void> decidePermission(PermissionRequest request, bool allowed) async {
    request.decided = allowed;
    notifyListeners();
    final res = await client.decidePermission(
      sessionId: request.sessionId,
      requestId: request.requestId,
      allowed: allowed,
    );
    switch (res) {
      case ApiOk():
        _permissions.remove(request);
        _addStatus(
          allowed
              ? 'Izin ${request.tool} disetujuji — eksekusi lanjut.'
              : 'Izin ${request.tool} ditolak — eksekusi berhenti.',
          icon: allowed ? 'ok' : 'warn',
        );
      case ApiErr(:final message):
        _addStatus(
          'Gagal mengirim keputusan izin — $message',
          error: true,
        );
    }
    notifyListeners();
  }

  // ---------------------------------------------------------- kartu status

  void _addStatus(
    String text, {
    String icon = 'info',
    bool error = false,
    bool pending = false,
  }) {
    _messages.add(
      ChatMessage(
        role: ChatRole.system,
        text: text,
        timestamp: DateTime.now(),
        error: error,
        pending: pending,
      ),
    );
    notifyListeners();
  }

  void _bootstrapLogAdd(String line) {
    _bootstrapLog.add('${DateTime.now().toIso8601String()} $line');
    if (_bootstrapLog.length > 200) {
      _bootstrapLog.removeRange(0, _bootstrapLog.length - 200);
    }
  }

  /// Membersihkan daftar pesan sesi aktif (tanpa menghapus di server).
  void clearMessages() {
    _messages.clear();
    _permissions.clear();
    notifyListeners();
  }

  /// Menyuntik pesan ke daftar tanpa menyentuh jaringan — dipakai pengujian
  /// untuk menyiapkan state UI (mis. kartu status, pesan streaming).
  void seed(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopFollowing());
    super.dispose();
  }
}
