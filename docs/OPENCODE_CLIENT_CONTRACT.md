# Kontrak Klien opencode — OAgents (Dart side)

Endpoint yang DIPAKAI aplikasi (dari REST API opencode, semua lewat `httpProxy`):
- `GET /api/info` — healthcheck; `{version, …}`
- `POST /api/session` — buat sesi; `{sessionID}`
- `GET /api/session` — daftar sesi
- `GET /api/session/:id/message` — pesan sesi
- `POST /api/session/:id/prompt` — kirim prompt; `{…}`
- `POST /api/session/:id/wait` — tunggu eksekusi selesai
- `GET /api/session/:id/log?follow=true` — SSE event: `session.execution.*`, teks parsial, panggilan tool, permintaan izin
- `POST /api/permission` (jika tersedia pada versi) — keputusan izin dari kartu inline
- `GET /api/model` / `GET /api/agent` — daftar model & agent aktif

Konvensi Dart:
1. `OpencodeClient` satu class dengan metode tipis; TIDAK ada logika provider.
2. Semua respons ke model Dart bebas UI (`ApiResult<T>`), dites terhadap server tiruan (`MockOpencodeServer`).
3. SSE diparse di `SseParser` (unit test penuh).
4. Kredensial disimpan `flutter_secure_storage`; disuntik sebagai env saat `startServer` — TIDAK pernah ditulis ke berkas.
