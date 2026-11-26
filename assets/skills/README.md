# Katalog Skills opencode — OAgents

Skill (paket instruksi markdown untuk agent opencode) yang dibundel
aplikasi di `assets/skills/<id>/`. Daftar mesin ada di `manifest.json`;
README ini versi manusia-baca dengan satu baris deskripsi per skill.
Skill dikopi Kotlin ke dalam `$HOME/.config/opencode/skill/` pada saat
rootfs dipasang (kontrak `docs/BRIDGE_CONTRACT.md`), sehingga agent
bisa memakainya tanpa unduhan.

| id | nama | deskripsi | sumber |
| --- | --- | --- | --- |
| `devtools/android-cli` | Android CLI Tools | Memakai adb, avdmanager, sdkmanager & cmdline-tools dari dalam rootfs. | `assets/skills/devtools/android-cli/` |
| `devtools/jetpack-compose` | Jetpack Compose | Migrasi layout XML → Compose, state, Material 3, dan preview di Android Studio. | `assets/skills/devtools/jetpack-compose/` |
| `devtools/testing-setup` | Testing Setup | Menyiapkan unit test JUnit, test UI Espresso/Compose & menjalankan `./gradlew test` via proot. | `assets/skills/devtools/testing-setup/` |
| `devtools/performance` | Performance | Profil dengan macrobenchmark, systrace/Perfetto, dan kurangi jank + startup lambat. | `assets/skills/devtools/performance/` |
| `devtools/security` | Security | Analisis keamanan statis, network security config, proguard/R8 & pen-test dasar. | `assets/skills/devtools/security/` |
| `devtools/play` | Play Store | Rilis APK/AAB, signing, keystore, jalur internal testing & kebijakan Play. | `assets/skills/devtools/play/` |
| `devtools/build-system/agp/agp-9-upgrade` | AGP 9 Upgrade | Menaikkan Android Gradle Plugin ke 9.x: migrasi DSL, JDK 17→21, dan perbaikan warning build. | `assets/skills/devtools/build-system/agp/agp-9-upgrade/` |

Tambah skill baru: buat folder `assets/skills/<id>/` berisi `SKILL.md`,
lalu tambahkan entri di `manifest.json` (id, name, description, path).
Id dipakai opencode sebagai nama skill saat instal; jangan ganti id yang
sudah ada karena sesi lama dapat merujuk padanya.
