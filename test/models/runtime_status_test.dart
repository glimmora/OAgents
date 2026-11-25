// Uji unit model runtime: RuntimeStage parse seluruh nilai, RootfsStatus/
// ServerStatus/ProgressEvent roundtrip, dan ApiResult fold — bebas UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:oagents/models/api_result.dart';
import 'package:oagents/models/runtime_status.dart';

void main() {
  group('RuntimeStage — parsing seluruh nilai', () {
    test('stageFromString memetakan semua nama tahap kontrak', () {
      expect(stageFromString('downloading'), RuntimeStage.downloading);
      expect(stageFromString('verifying'), RuntimeStage.verifying);
      expect(stageFromString('extracting'), RuntimeStage.extracting);
      expect(stageFromString('installing'), RuntimeStage.installing);
      expect(stageFromString('booting'), RuntimeStage.booting);
      expect(stageFromString('ready'), RuntimeStage.ready);
      expect(stageFromString('error'), RuntimeStage.error);
    });

    test('huruf besar/kecil & null → idle (default aman)', () {
      expect(stageFromString('DOWNLOADING'), RuntimeStage.downloading);
      expect(stageFromString(null), RuntimeStage.idle);
      expect(stageFromString(''), RuntimeStage.idle);
      expect(stageFromString('tidak-dikenal'), RuntimeStage.idle);
    });

    test('stageLabel memberi label Indonesia tiap tahap', () {
      expect(stageLabel(RuntimeStage.downloading), 'Mengunduh rootfs');
      expect(stageLabel(RuntimeStage.ready), 'Siap');
      expect(stageLabel(RuntimeStage.error), 'Galat');
      expect(stageLabel(RuntimeStage.idle), 'Menganggur');
    });
  });

  group('RootfsStatus — fromJson roundtrip', () {
    test('terpasang penuh terparse semua field', () {
      final s = RootfsStatus.fromJson(<String, dynamic>{
        'installed': true,
        'version': '2.4.1',
        'sizeMB': 80,
        'ok': true,
      });
      expect(s.installed, isTrue);
      expect(s.version, '2.4.1');
      expect(s.sizeMB, 80);
      expect(s.ok, isTrue);
    });

    test('JSON kosong/aneh → nilai default aman tanpa lempar', () {
      final s = RootfsStatus.fromJson(<String, dynamic>{});
      expect(s.installed, isFalse);
      expect(s.version, '');
      expect(s.sizeMB, 0);
      expect(s.ok, isFalse);
    });
  });

  group('ServerStatus — fromJson & uptimeLabel', () {
    test('roundtrip running pid port upMs', () {
      final s = ServerStatus.fromJson(<String, dynamic>{
        'running': true,
        'pid': 4321,
        'port': 4096,
        'upMs': 3661000,
      });
      expect(s.running, isTrue);
      expect(s.pid, 4321);
      expect(s.port, 4096);
      expect(s.uptimeLabel, '01:01:01');
    });

    test('upMs nol → label strip em-dash, angka teks toleran', () {
      final s = ServerStatus.fromJson(<String, dynamic>{
        'running': false,
        'pid': '1234',
        'port': 4096,
        'upMs': 0,
      });
      expect(s.uptimeLabel, '—');
      expect(s.pid, 1234);
    });
  });

  group('ProgressEvent — clamping persen', () {
    test('pct dibatasi 0..100 dan dibulatkan', () {
      final over = ProgressEvent.fromJson(<String, dynamic>{
        'stage': 'downloading',
        'pct': 140,
      });
      expect(over.pct, 100);
      final under = ProgressEvent.fromJson(<String, dynamic>{
        'stage': 'downloading',
        'pct': -5,
      });
      expect(under.pct, 0);
      final frac = ProgressEvent.fromJson(<String, dynamic>{
        'stage': 'verifying',
        'pct': 42.6,
      });
      expect(frac.pct, 43);
      expect(frac.detail, '');
    });

    test('pct NaN → 0 (tidak melempar)', () {
      final e = ProgressEvent.fromJson(<String, dynamic>{
        'stage': 'booting',
        'pct': double.nan,
      });
      expect(e.pct, 0);
    });
  });

  group('ApiResult — fold / map / orDefault', () {
    test('ApiOk.map memanggil cabang ok dengan nilai', () {
      const res = ApiOk<int>(42);
      final out = res.map(ok: (v) => v + 1, error: (e) => -1);
      expect(out, 43);
      expect(res.orDefault, 42);
      expect(res.orNull, 42);
    });

    test('ApiErr.map memanggil cabang error & fallback di orDefault', () {
      const res = ApiErr<int>('server mati', code: 500, fallback: 0);
      final out = res.map(ok: (v) => v, error: (e) => -1);
      expect(out, -1);
      expect(res.orDefault, 0);
      expect(res.orNull, isNull);
      expect(res.message, 'server mati');
      expect(res.code, 500);
    });

    test('ApiResult bebas UI — tidak pernah lempar saat dibaca sebagai data',
        () {
      ApiResult<String> res = const ApiErr('belum siap', fallback: 'n/a');
      expect(res.orDefault, 'n/a');
      res = const ApiOk('siap');
      switch (res) {
        case ApiOk(value: final v):
          expect(v, 'siap');
        case ApiErr():
          fail('seharusnya cabang ok');
      }
    });
  });
}
