# Daftar Seluruh Test OAgents

Ringkasan semua berkas test + jumlah test per berkas. Angka dihitung dari
penanda `test(` / `testWidgets(` per berkas; `grep -Rc "test(" test/
integration_test/` memberi 78 (test saja) dan 99 bila `testWidgets` ikut.

| berkas | jumlah test | cakupan |
| --- | --- | --- |
| `test/services/sse_parser_test.dart` | 20 | Parsing SSE: event/data/id, multiline reassembly, komentar, CRLF/CR, event tanpa data, dispatch ganda, chunk terputus, 1000 event, id numerik, session.execution.partial, sseDataToJson/sseEventToMap. |
| `test/services/opencode_client_test.dart` | 24 | getInfo/createSession/listSessions/sendPrompt/waitForSession, decidePermission varian endpoint, followLog 404-stop & retry 500, listModels fallback, listAgents, pembentukan path (urlJoin). |
| `test/services/runtime_bridge_test.dart` | 12 | rootfsStatus true/false, startServer {ok,pid,port} + argumen env/workDir + galat, serverStatus running + uptime, stopServer, execInRootfs stdout/stderr, httpProxy {status,body}, event stream progress. |
| `test/models/chat_message_test.dart` | 9 | ChatMessage konstruksi/copyWith/pending-streamed/toolCalls/error, PermissionRequest keputusan & kesetaraan, ToolCallView, ChatRole. |
| `test/models/runtime_status_test.dart` | 12 | RuntimeStage parse semua nilai + stageLabel, RootfsStatus/ServerStatus/ProgressEvent fromJson (clamp pct & NaN), ApiResult fold/map/orDefault. |
| `test/widgets/status_card_test.dart` | 10 | StatusCard render teks/progress/onTap/compact + PermissionCard Setuju/Tolak callback & tanpa SnackBar. |
| `test/widgets/permission_card_test.dart` | 4 | PermissionCard klik Setuju/Tolak, status diputuskan, tanpa SnackBar. |
| `test/screens/chat_screen_test.dart` | 6 | Render daftar pesan, input enabled, kirim → controller, indikator pending, StatusCard saat tahap berjalan, tanpa SnackBar. |
| `integration_test/app_e2e_test.dart` | 2 | E2E --dart-define E2E_FAKE_BRIDGE=true: FakeBridge rootfs installed, startServer, serverStatus ready, sesi s1, streaming Halo, pindah tab Runtime, kartu status, tanpa SnackBar. |

**Total: 99 test.**

Aturan yang dipenuhi semua berkas: import hanya `flutter_test` (plus
`integration_test`, `provider`, `flutter/services` untuk keperluan binding)
dan `package:oagents/...`; fake manual tanpa mockito; tanpa jaringan; nama
group/test berbahasa Indonesia.
