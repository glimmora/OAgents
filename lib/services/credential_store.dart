import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan kredensial provider per kunci — aman di `flutter_secure_storage`.
///
/// Kredensial TIDAK pernah ditulis ke berkas; disuntik sebagai env saat
/// `RuntimeBridge.startServer` (lihat OPENCODE_CLIENT_CONTRACT.md).
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _prefix = 'provider.';

  /// Menyimpan API key untuk satu provider (contoh: `openai`, `anthropic`).
  Future<void> set(String provider, String apiKey) {
    return _storage.write(key: _prefixKey(provider), value: apiKey);
  }

  /// Mengambil API key provider; null bila belum ada.
  Future<String?> get(String provider) {
    return _storage.read(key: _prefixKey(provider));
  }

  /// Menghapus API key provider.
  Future<void> delete(String provider) {
    return _storage.delete(key: _prefixKey(provider));
  }

  /// Daftar nama provider yang sudah menyimpan kredensial.
  Future<List<String>> listProviders() async {
    final all = await _storage.readAll();
    return all.keys
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(_prefix.length))
        .toList()
      ..sort();
  }

  /// Membaca semua kredensial sebagai env map — dipakai `startServer`
  /// untuk menyetor `K1=V1` ke dalam proot.
  Future<Map<String, String>> readAllEnv() async {
    final all = await _storage.readAll();
    return {
      for (final e in all.entries)
        if (e.key.startsWith(_prefix))
          _envName(e.key.substring(_prefix.length)): e.value,
    };
  }

  static String _prefixKey(String provider) => '$_prefix$provider';

  /// `provider.openai` → env `OPENCODE_OPENAI_API_KEY` (nama env yang dibaca
  /// opencode untuk API key tiap provider).
  static String _envName(String provider) {
    final p = provider.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');
    return 'OPENCODE_${p}_API_KEY';
  }
}
