// Driver untuk `flutter drive` — resep resmi CI integration_test:
// menjalankan integration_test/ di device nyata (emulator) TANPA melalui
// package:test harness, sehingga fase "loading" (gradle build + install APK
// yang di TCG bisa ~10 menit) tidak dijatuhkan timer 12 menit default.
//
// Retry connect: di TCG (software rendering), isolate sering belum runnable
// saat driver pertama konek → getIsolate() mengembalikan Sentinel Collected
// ("isolate taking unusually long time to initialize"). Ulangi connect
// hingga 4x dengan jeda 30 dtk — race VM-service klasik di emulator lambat.
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  FlutterDriver? driver;
  Object? lastError;
  for (var attempt = 1; attempt <= 4; attempt++) {
    try {
      driver = await FlutterDriver.connect();
      break;
    } catch (e) {
      lastError = e;
      // ignore: avoid_print — keluaran diagnostik CLI driver.
      print('Connect attempt $attempt gagal: $e — ulang dalam 30 dtk.');
      await Future<void>.delayed(const Duration(seconds: 30));
    }
  }
  if (driver == null) {
    throw StateError('Driver gagal connect setelah 4 percobaan: $lastError');
  }
  await driver.waitUntilFirstFrameRasterized();
  final String result = await driver.requestData('integration-test-done',
      timeout: const Duration(minutes: 60));
  // ignore: avoid_print — driver CLI flutter drive memang keluaran stdout.
  print('Hasil integration test: $result');
  await driver.close();
}
