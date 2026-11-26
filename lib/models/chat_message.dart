import 'package:flutter/foundation.dart';

/// Peran pengirim pesan pada percakapan.
enum ChatRole { user, assistant, system }

/// Satu panggilan tool yang melekat pada pesan assistant.
@immutable
class ToolCallView {
  const ToolCallView({
    required this.tool,
    required this.input,
    this.running = true,
    this.output,
  });

  /// Nama tool, mis. `bash` atau `write`.
  final String tool;

  /// Ringkasan perintah/argumen (sudah dipangkas untuk kartu).
  final String input;

  /// Masih berjalan atau sudah selesai.
  final bool running;

  /// Keluaran ringkas tool bila sudah ada.
  final String? output;
}

/// Permintaan izin tool yang harus diputuskan pengguna lewat kartu inline.
/// `decided` mutable dengan sengaja (diputuskan satu kali dari UI), jadi
/// kelas ini tidak const — dibuat per permintaan, tidak pernah nilai konst.
// ignore: must_be_immutable
class PermissionRequest {
  PermissionRequest({
    required this.requestId,
    required this.tool,
    required this.summary,
    required this.sessionId,
    this.decided,
  });

  final String requestId;
  final String tool;

  /// Ringkasan perintah yang akan dijalankan.
  final String summary;
  final String sessionId;

  /// `null` = belum diputuskan, `true` = disetujuji, `false` = ditolak.
  /// Mutable secara sadar: diputuskan satu kali dari kartu izin inline,
  /// karenanya constructor tidak const dan kelas tidak dipakai sebagai nilai
  /// konst di UI.
  bool? decided;
  @override
  bool operator ==(Object other) =>
      other is PermissionRequest && other.requestId == requestId;

  @override
  int get hashCode => requestId.hashCode;
}

/// Satu pesan pada percakapan — pengguna, assistant, atau sistem.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.toolCalls = const [],
    this.permissionRequest,
    this.pending = false,
    this.streamed = false,
    required this.timestamp,
    this.error = false,
  });

  ChatMessage copyWith({
    ChatRole? role,
    String? text,
    List<ToolCallView>? toolCalls,
    PermissionRequest? permissionRequest,
    bool? pending,
    bool? streamed,
    DateTime? timestamp,
    bool? error,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      text: text ?? this.text,
      toolCalls: toolCalls ?? this.toolCalls,
      permissionRequest: permissionRequest ?? this.permissionRequest,
      pending: pending ?? this.pending,
      streamed: streamed ?? this.streamed,
      timestamp: timestamp ?? this.timestamp,
      error: error ?? this.error,
    );
  }

  final ChatRole role;
  final String text;
  final List<ToolCallView> toolCalls;
  final PermissionRequest? permissionRequest;

  /// Sedang menunggu respons (menampilkan indikator mengetik).
  final bool pending;

  /// Teks disusun dari streaming SSE (tampil real-time).
  final bool streamed;

  final DateTime timestamp;
  final bool error;
}
