import 'package:flutter/foundation.dart';

/// Ringkasan satu sesi opencode dari `GET /api/session`.
@immutable
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.parentID,
  });

  /// Membaca dari JSON mentah dengan toleransi bentuk field yang berbeda-beda
  /// antar versi opencode (`id`/`sessionID`, `title`/`name`, `time`/`updatedAt`).
  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    final rawTime = json['updatedAt'] ?? json['time'] ?? json['modifiedAt'];
    DateTime? parsed;
    if (rawTime is int) {
      parsed = DateTime.fromMillisecondsSinceEpoch(
        rawTime > 1000000000000 ? rawTime : rawTime * 1000,
      );
    } else if (rawTime is String) {
      parsed = DateTime.tryParse(rawTime);
    }
    return SessionSummary(
      id: (json['id'] ?? json['sessionID'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Tanpa judul').toString(),
      updatedAt: parsed,
      parentID: json['parentID']?.toString(),
    );
  }

  final String id;
  final String title;
  final DateTime? updatedAt;
  final String? parentID;

  String get updatedLabel {
    final t = updatedAt;
    if (t == null) return 'waktu tidak diketahui';
    final ymd = '${t.year}-${_two(t.month)}-${_two(t.day)}';
    return '$ymd ${_two(t.hour)}:${_two(t.minute)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
