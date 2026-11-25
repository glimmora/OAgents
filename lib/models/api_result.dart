import 'package:flutter/foundation.dart';

/// Hasil panggilan API yang bebas UI: sukses ([ApiOk]) atau gagal ([ApiErr]).
/// Tidak pernah memicu popup notifikasi — pemanggil membaca status sebagai data.
sealed class ApiResult<T> {
  const ApiResult();

  /// Nilai saat sukses.
  R map<R>({
    required R Function(T value) ok,
    required R Function(ApiErr<T> err) error,
  }) {
    final self = this;
    if (self is ApiOk<T>) return ok(self.value);
    return error(self as ApiErr<T>);
  }

  /// Nilai default saat gagal, tanpa melempar.
  T get orDefault => map(ok: (v) => v, error: (e) => e.fallback);

  /// Nilai nullable — `null` saat gagal.
  T? get orNull => map(ok: (v) => v, error: (_) => null);
}

final class ApiOk<T> extends ApiResult<T> {
  const ApiOk(this.value);

  final T value;

  @override
  String toString() => 'ApiOk(${value.runtimeType})';
}

final class ApiErr<T> extends ApiResult<T> {
  const ApiErr(this.message, {this.code, required this.fallback});

  /// Pesan galat yang siap ditampilkan pada kartu status inline.
  final String message;

  /// Kode status HTTP bila berasal dari respons proxy, null bila galat lain.
  final int? code;

  /// Nilai pengganti supaya `orDefault` tetap aman dipakai tanpa cek cabang.
  final T fallback;

  @override
  String toString() => 'ApiErr($code: $message)';
}

@immutable
class ApiErrView {
  const ApiErrView({required this.message, this.code});

  final String message;
  final int? code;
}
