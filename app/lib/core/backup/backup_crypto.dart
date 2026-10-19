import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// File magic of a Mediahro backup (CORE-014).
const List<int> backupMagic = [
  0x4D,
  0x48,
  0x52,
  0x4F,
  0x42,
  0x4B,
  0x31,
  0x0A,
]; // "MHROBK1\n"

final class BackupDecryptError implements Exception {
  const BackupDecryptError(this.reason);

  /// `notABackup`, `wrongPassphrase` (or corrupt), `unsupportedVersion`.
  final String reason;

  @override
  String toString() => 'BackupDecryptError($reason)';
}

/// Encrypts a JSON payload: gzip, then AES-256-GCM with a key from
/// PBKDF2-HMAC-SHA256 ([iterations], 16-byte salt). Runs on an isolate.
///
/// Layout: magic · u32 header length · header JSON (kdf, salt, nonce) ·
/// ciphertext · 16-byte tag. The header is authenticated as AAD.
Future<Uint8List> encryptBackup(
  Map<String, Object?> payload,
  String passphrase, {
  int iterations = 310000,
}) => Isolate.run(() async {
  final rnd = Random.secure();
  final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
  final key = await _key(passphrase, salt, iterations);
  final aes = AesGcm.with256bits();
  final nonce = aes.newNonce();
  final header = utf8.encode(
    jsonEncode({
      'v': 1,
      'kdf': 'pbkdf2-hmac-sha256',
      'iter': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipher': 'aes-256-gcm',
    }),
  );
  final plain = gzip.encode(utf8.encode(jsonEncode(payload)));
  final box = await aes.encrypt(
    plain,
    secretKey: key,
    nonce: nonce,
    aad: header,
  );
  final out = BytesBuilder()
    ..add(backupMagic)
    ..add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List())
    ..add(header)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return out.takeBytes();
});

Future<Map<String, Object?>> decryptBackup(
  Uint8List file,
  String passphrase,
) => Isolate.run(() async {
  if (file.length < backupMagic.length + 4 + 16) {
    throw const BackupDecryptError('notABackup');
  }
  for (var i = 0; i < backupMagic.length; i++) {
    if (file[i] != backupMagic[i]) throw const BackupDecryptError('notABackup');
  }
  final hlen = ByteData.sublistView(
    file,
    backupMagic.length,
    backupMagic.length + 4,
  ).getUint32(0);
  final hstart = backupMagic.length + 4;
  if (hlen > 4096 || hstart + hlen + 16 > file.length) {
    throw const BackupDecryptError('notABackup');
  }
  final headerBytes = file.sublist(hstart, hstart + hlen);
  final h = jsonDecode(utf8.decode(headerBytes)) as Map<String, Object?>;
  if (h['v'] != 1 || h['cipher'] != 'aes-256-gcm') {
    throw const BackupDecryptError('unsupportedVersion');
  }
  final iterations = h['iter']! as int;
  if (iterations < 100000 || iterations > 10000000) {
    throw const BackupDecryptError('unsupportedVersion');
  }
  final key = await _key(
    passphrase,
    base64Decode(h['salt']! as String),
    iterations,
  );
  final body = file.sublist(hstart + hlen);
  final box = SecretBox(
    body.sublist(0, body.length - 16),
    nonce: base64Decode(h['nonce']! as String),
    mac: Mac(body.sublist(body.length - 16)),
  );
  final List<int> plain;
  try {
    plain = await AesGcm.with256bits().decrypt(
      box,
      secretKey: key,
      aad: headerBytes,
    );
  } on SecretBoxAuthenticationError {
    throw const BackupDecryptError('wrongPassphrase');
  }
  // Bounded inflate: a backup never decompresses beyond 512 MiB.
  final inflated = BytesBuilder(copy: false);
  await for (final chunk in Stream<List<int>>.value(
    plain,
  ).transform(gzip.decoder)) {
    inflated.add(chunk);
    if (inflated.length > 512 << 20) {
      throw const BackupDecryptError('notABackup');
    }
  }
  final v = jsonDecode(utf8.decode(inflated.takeBytes()));
  if (v is! Map<String, Object?>) throw const BackupDecryptError('notABackup');
  return v;
});

Future<SecretKey> _key(String passphrase, List<int> salt, int iterations) =>
    Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
