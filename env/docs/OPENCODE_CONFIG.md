# Konfigurasi opencode untuk OAgents

OAgents tidak punya konfigurasi provider sendiri: seluruh pengaturan agent,
model, izin, dan tema dikelola oleh berkas konfigurasi opencode
(`opencode.json` di dalam `$HOME/.config/opencode/` pada rootfs). Template
siap-salin ada di `env/opencode-config-template.json`. Nilai `${MODEL}` dan
`${AGENT}` diisi saat bootstrap Kotlin dari `env/env.lock` + pilihan
pengguna di layar Runtime; contoh pengisian nyata: `"model": "anthropic/claude-sonnet-5-5"`
dan `"default_agent": "build"` (agent bawaan opencode; `plan` untuk mode
hanya-baca). Berkas memakai `$schema` generasi 2 terkini
(`https://opencode.ai/config.json`) — editor menawarkan autocomplete penuh
saat berkas dibuka.

## Daftar field template

- `$schema` — URL skema generasi 2 terkini (`https://opencode.ai/config.json`)
  untuk validasi & autocomplete editor.
- `model` — model default dalam format `provider/modelID`; placeholder
  `${MODEL}` diganti bootstrap.
- `default_agent` — agent yang dipakai bila sesi tidak menyebut satu
  (`build`, `plan`); placeholder `${AGENT}`.
- `share` — telemetri berbagi sesi (default `false` di template).
- `update` — perilaku pembaruan biner: `disable` | `notify` | `auto`.
- `skills` — folder skill yang dibundel OAgents
  (`~/.config/opencode/skill`, diisi dari `assets/skills/manifest.json`).
- `instructions` — berkas instruksi tambahan (mis. `AGENTS.md`).
- `theme` — tema antarmuka (nama + mode terang/gelap).
- `permissions` — daftar aturan `{action, resource, effect}` dengan effect
  `allow`/`deny`/`ask`; kartu izin inline OAgents menghormati `ask`.
