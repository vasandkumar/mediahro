import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/features/photos/vault/vault_bytes.dart';
import 'package:mediahro/features/photos/vault/vault_framing.dart';
import 'package:mediahro/platform/vault_crypto.dart';

/// A container's secret, sealed in a file (IMG-011, ADR-039 amendment 2).
///
/// Each vault folder has a random 32-byte secret S. Everything in the folder
/// is wrapped under a keystore handle opened with S; S itself lives only
/// here, sealed under a handle opened with the PIN's token. So a wrong PIN
/// cannot unseal S, a right one can, and changing the PIN seals the same S
/// again without touching a single file.
final class VaultSecretFile {
  const VaultSecretFile._();

  static const String name = 'secret.mv';

  /// The file written for a new PIN beside the old one (see
  /// `VaultManager.changePin`).
  static const String nextSuffix = '.next';

  /// The size of S.
  static const int length = 32;

  static Uint8List _context(String folder) =>
      Uint8List.fromList(utf8.encode('secret:$folder'));

  /// Seals [secret] under [pinHandle] (a handle opened with a PIN token) and
  /// writes it to [target] through a part file.
  static Future<void> write({
    required File target,
    required VaultCryptoFacade crypto,
    required VaultKeyHandle pinHandle,
    required Uint8List secret,
    required String folder,
  }) async {
    final key = await crypto.newFileKey(pinHandle);
    final part = File('${target.path}.part');
    try {
      final raf = await part.open(mode: FileMode.write);
      try {
        await VaultSealer(crypto).seal(
          key: key,
          plain: Stream.value(secret),
          plainLength: secret.length,
          out: (b) async => await raf.writeFrom(b),
          embedKey: true,
          context: _context(folder),
        );
        await raf.flush();
      } finally {
        await raf.close();
      }
      await part.rename(target.path);
    } on Object {
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } on FileSystemException {
          // Left for the next write over it.
        }
      }
      rethrow;
    }
  }

  /// Reads S from [file] with [pinHandle]. A handle opened with the wrong
  /// token fails with the facade's `keyLost`; a damaged file with
  /// [VaultCorrupt]. The caller zeroes the result.
  static Future<Uint8List> read({
    required File file,
    required VaultCryptoFacade crypto,
    required VaultKeyHandle pinHandle,
    required String folder,
  }) async {
    final reader = await VaultReader.open(
      crypto: crypto,
      source: MemoryVaultSource(await file.readAsBytes()),
      master: pinHandle,
      context: _context(folder),
    );
    final s = await reader.readAll();
    if (s.length != length) throw const VaultCorrupt('secret has a wrong size');
    // The chunk the facade handed back may be a read-only view of its buffer.
    final copy = ownedCopy(s);
    wipe(s);
    return copy;
  }
}
