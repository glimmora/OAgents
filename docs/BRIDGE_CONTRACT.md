# Kontrak Bridge Native — OAgents

Satu-satunya dokumen kebenaran untuk MethodChannel `oagents/runtime`.
Dart memanggil; Kotlin (MainActivity + RuntimePlugin) mengeksekusi; hasil JSON.

## Kanal
`oagents/runtime` — semua metode di bawah. Semua argumen & hasil: JSON.

## Metode

| Metode | Argumen | Hasil | Keterangan |
| --- | --- | --- | --- |
| `rootfsStatus` | – | `{installed:bool, version:str, sizeMB:num, ok:bool}` | Cek rootfs + biner opencode terpasang |
| `installRootfs` | `{rootfsUrl, opencodeUrl, version}` | `{ok, stage, detail}` async event via `onProgress` | Unduh→verifikasi→ekstrak→pasang opencode; event `oagents/progress` |
| `startServer` | `{port, env:{K1:V1,…}, workDir}` | `{ok, pid, port}` | proot + opencode serve; auto-restart di Kotlin jika mati |
| `stopServer` | – | `{ok}` | SIGTERM pid tree proot |
| `serverStatus` | – | `{running:bool, pid, port, upMs}` | healthcheck `/api/info` |
| `execInRootfs` | `{cmd:str, timeoutMs:num}` | `{ok, exitCode, stdout, stderr}` | dijalankan lewat proot -R rootfs |
| `httpProxy` | `{method,path,body,headers}` | `{status, body}` | proxy ke 127.0.0.1:PORT; Dart tidak boleh buka soket lokal sendiri |

## Event channel
`oagents/progress` — `{stage: downloading|verifying|extracting|installing|booting, pct: 0-100, detail: str}`

## Aturan
1. Semua JSON, tidak ada tipe native lain melintas channel.
2. Dart tidak pernah menulis berkas di luar folder aplikasi; Kotlin mengikat `workDir` aplikasi sebagai `/rootfs-bind` di dalam proot.
3. Port hanya 127.0.0.1; tidak ada binding 0.0.0.0.
4. Kegagalan dikembalikan `{ok:false, error:str}` — TIDAK ada Toast/Snackbar native; UI Dart menampilkan kartu status inline.
