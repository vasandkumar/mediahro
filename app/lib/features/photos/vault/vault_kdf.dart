import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2 rounds for a new vault (ADR-040: at least 600,000).
const int vaultKdfIterations = 600000;

/// The PIN-derived token of a vault: PBKDF2-HMAC-SHA256 over the PIN with the
/// vault's [salt], on a worker isolate so the screen stays alive. The token
/// is the 32-byte secret every index is bound to; it is never stored.
Future<Uint8List> derivePinToken(String pin, Uint8List salt, int iterations) =>
    Isolate.run(() => pbkdf2Sha256(utf8.encode(pin), salt, iterations));

/// PBKDF2-HMAC-SHA256, one 32-byte block (RFC 8018). Synchronous: call it
/// off the UI isolate.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
  final t = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var k = 0; k < 32; k++) {
      t[k] ^= u[k];
    }
  }
  return t;
}
