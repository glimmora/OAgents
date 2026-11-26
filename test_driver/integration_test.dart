// Driver untuk `flutter drive` — resep resmi CI integration_test:
// menjalankan integration_test/ di device nyata (emulator) TANPA melalui
// package:test harness, sehingga fase "loading" (gradle build + install APK
// yang di TCG bisa ~10 menit) tidak dijatuhkan timer 12 menit default.
// Driver hanya connect ke VM Service dan menunggu test selesai; batas waktu
// adalah job timeout workflow (75 menit), bukan timer per-suite package:test.
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final FlutterDriver driver = await FlutterDriver.connect();
  await driver.waitUntilFirstFrameRasterized();
  final String result = await driver.requestData('integration-test-done',
      timeout: const Duration(minutes: 60));
  // ignore: avoid_print — driver CLI flutter drive memang keluaran stdout.
  print('Hasil integration test: $result');
  await driver.close();
}
