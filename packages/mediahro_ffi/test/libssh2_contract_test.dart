// libssh2 + WinCNG (ADR-017): the bindings lane C4's Windows SftpFacade
// drives. Runs where the mediahro-deps Windows archive provides ssh2.dll /
// libssh2.dll; skipped elsewhere with the reason.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

DynamicLibrary? _open() {
  if (!Platform.isWindows) return null;
  for (final name in const ['ssh2.dll', 'libssh2.dll']) {
    try {
      return DynamicLibrary.open(name);
      // DynamicLibrary.open reports a missing library only as ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      // try the next name
    }
  }
  return null;
}

void main() {
  final lib = _open();
  final skip = !Platform.isWindows
      ? 'Windows only: Android and Apple SFTP use the OS SSH stack (ADR-017)'
      : lib == null
      ? 'blocked: STATUS §3 — mediahro-deps libssh2 for Windows (B4c)'
      : null;

  test('NET-004 SFTP attribute layout matches the Windows ABI', () {
    // unsigned long is 32-bit on Windows (LLP64); filesize is 64-bit.
    expect(sizeOf<Ssh2SFTP_ATTRIBUTES>(), Platform.isWindows ? 40 : 56);
  });

  test('NET-004 libssh2 initialises and reports its version', () {
    final b = Ssh2Bindings(lib!);
    expect(b.libssh2_init(0), 0);
    final v = b.libssh2_version(0).cast<Utf8>().toDartString();
    expect(v, startsWith('1.11'));
    final s = b.libssh2_session_init_ex(nullptr, nullptr, nullptr, nullptr);
    expect(s, isNot(nullptr));
    b
      ..libssh2_session_set_blocking(s, 1)
      ..libssh2_session_free(s)
      ..libssh2_exit();
  }, skip: skip);
}
