# OAgents

Aplikasi Android agent AI dengan **opencode CLI** sebagai engine — bukan provider AI tertanam.

Aplikasi memasang lingkungan Linux (rootfs Alpine arm64 + proot) di penyimpanan internal, menjalankan `opencode serve` sebagai proses latar, dan menjadi klien grafisnya (REST API + SSE). Semua provider/model dikonfigurasi lewat opencode; API key disimpan aman di Android Keystore dan disuntik sebagai env.

> Status: pengembangan awal (v0.1.0). Pipeline CI/CD di GitHub Actions — tanpa build lokal.

## Arsitektur (singkat)
```
UI Flutter (chat, sesi, kartu izin inline — tanpa snackbar/popup teks)
  └─ MethodChannel oagents/runtime (kontrak: docs/BRIDGE_CONTRACT.md)
      └─ Kotlin: proot -R rootfs + opencode serve (127.0.0.1:4096)
          └─ REST/SSE → docs/OPENCODE_CLIENT_CONTRACT.md
```
Lingkungan: rootfs **Alpine** (musl — biner opencode `linux-arm64-musl`) via **proot**; detail versi terkunci di `env/env.lock`.

## Pengembangan
- `flutter run` — aplikasi; bootstrap runtime otomatis saat pertama kali.
- `flutter test` — unit & widget.
- `flutter test integration_test` — e2e di emulator/API 35.
- CI: push/PR → lint+unit (gate murah) → build APK → e2e emulator → auto-fix.
- Rilis: tag `v*` → APK signed + AAB + GitHub Release (keystore via secrets).

## Lisensi
MIT.
