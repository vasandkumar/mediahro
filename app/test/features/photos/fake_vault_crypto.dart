import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mediahro/features/photos/vault/vault_kdf.dart';
import 'package:mediahro/platform/security.dart';
import 'package:mediahro/platform/vault_crypto.dart';

/// OS crypto for tests: AES-256-GCM with the framing left to the caller, as
/// the real facade does. (`package:cryptography` is for tests only; the app's
/// vault code does not use it.) Two "keystore keys" exist, one for the
/// biometry-protected master and one for the plain master.
final class FakeVaultCrypto implements VaultCryptoFacade {
  FakeVaultCrypto({int seed = 7}) : _random = Random(seed) {
    _masters[false] = _bytes(32);
    _masters[true] = _bytes(32);
  }

  final Random _random;
  final AesGcm _aes = AesGcm.with256bits();
  final Map<bool, Uint8List> _masters = {};
  final Map<int, bool> _open = {};
  final Map<int, Uint8List> _secrets = {};
  var _next = 1;

  /// Calls and handles, for assertions.
  final List<String> calls = [];
  int get openHandles => _open.length;

  /// Make the next `openMasterKey` fail with this error (once, per kind).
  VaultCryptoError? failPlainOpen;
  VaultCryptoError? failBiometricOpen;

  /// Every `seal` and `open` call throws this.
  VaultCryptoError? failChunks;

  int sealCalls = 0;
  int openCalls = 0;

  Uint8List _bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  /// Pretends the OS invalidated the biometry-protected key.
  void invalidateBiometricKey() => _masters[true] = _bytes(32);

  /// Pretends the keystore lost every key.
  void loseKeys() {
    _masters[false] = _bytes(32);
    _masters[true] = _bytes(32);
    _lost = true;
  }

  // True from loseKeys until reset: opening any key says keyLost, as the real
  // facade does when the keystore entry is gone.
  bool _lost = false;

  @override
  Future<VaultKeyHandle> openMasterKey({
    required bool requireBiometry,
    Uint8List? secret,
  }) async {
    calls.add('openMaster:$requireBiometry');
    if (_lost) throw const VaultCryptoException(VaultCryptoError.keyLost);
    final fail = requireBiometry ? failBiometricOpen : failPlainOpen;
    if (fail != null) throw VaultCryptoException(fail);
    final id = _next++;
    _open[id] = requireBiometry;
    if (secret != null) _secrets[id] = Uint8List.fromList(secret);
    return VaultKeyHandle(id);
  }

  Uint8List _masterOf(VaultKeyHandle h) {
    final bio = _open[h.id];
    if (bio == null) {
      throw const VaultCryptoException(VaultCryptoError.unavailable, 'closed');
    }
    final master = _masters[bio]!;
    final s = _secrets[h.id];
    if (s == null) return master;
    return Uint8List.fromList([
      for (var i = 0; i < master.length; i++) master[i] ^ s[i % s.length],
    ]);
  }

  // Wrapped key = nonce | AES-GCM(master, fileKey) | tag.
  Future<Uint8List> _wrap(Uint8List master, Uint8List fileKey) async {
    final nonce = _bytes(12);
    final box = await _aes.encrypt(
      fileKey,
      secretKey: SecretKey(master),
      nonce: nonce,
    );
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> _unwrap(VaultKeyHandle h, Uint8List wrapped) async {
    final master = _masterOf(h);
    try {
      final box = SecretBox(
        wrapped.sublist(12, wrapped.length - 16),
        nonce: wrapped.sublist(0, 12),
        mac: Mac(wrapped.sublist(wrapped.length - 16)),
      );
      return Uint8List.fromList(
        await _aes.decrypt(box, secretKey: SecretKey(master)),
      );
    } on SecretBoxAuthenticationError {
      // A wrong secret looks like a lost key, as on the real facade.
      throw VaultCryptoException(
        _secrets.containsKey(h.id)
            ? VaultCryptoError.keyLost
            : VaultCryptoError.keyInvalidated,
      );
    }
  }

  @override
  Future<WrappedKey> newFileKey(VaultKeyHandle master) async {
    calls.add('newFileKey');
    return WrappedKey(
      master: master,
      bytes: await _wrap(_masterOf(master), _bytes(32)),
    );
  }

  @override
  Future<WrappedKey> adoptFileKey(
    VaultKeyHandle master,
    Uint8List wrapped,
  ) async {
    calls.add('adoptFileKey');
    await _unwrap(master, wrapped);
    return WrappedKey(master: master, bytes: Uint8List.fromList(wrapped));
  }

  @override
  Future<Uint8List> seal(
    WrappedKey key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List plaintext,
  ) async {
    sealCalls++;
    if (failChunks != null) throw VaultCryptoException(failChunks!);
    final fileKey = await _unwrap(key.master, key.bytes);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(fileKey),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  @override
  Future<Uint8List> open(
    WrappedKey key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List sealed,
  ) async {
    openCalls++;
    if (failChunks != null) throw VaultCryptoException(failChunks!);
    final fileKey = await _unwrap(key.master, key.bytes);
    try {
      final box = SecretBox(
        sealed.sublist(0, sealed.length - 16),
        nonce: nonce,
        mac: Mac(sealed.sublist(sealed.length - 16)),
      );
      return Uint8List.fromList(
        await _aes.decrypt(box, secretKey: SecretKey(fileKey), aad: aad),
      );
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoException(VaultCryptoError.integrityFailure);
    }
  }

  /// Set to make [reset] fail.
  VaultCryptoError? failReset;

  /// Set to make [reset] fail with something that is not a keystore error.
  Error? failResetWith;
  int resets = 0;

  @override
  Future<void> reset() async {
    calls.add('reset');
    if (failResetWith != null) throw failResetWith!;
    if (failReset != null) throw VaultCryptoException(failReset!);
    resets++;
    // New keys, as a new keystore entry would be; open handles are closed.
    _open.clear();
    loseKeys();
    _lost = false;
  }

  @override
  Future<void> close(VaultKeyHandle handle) async {
    calls.add('close');
    _open.remove(handle.id);
    _secrets.remove(handle.id);
  }
}

/// Secure storage in memory.
final class MemorySecureStorage implements SecureStorageFacade {
  final Map<String, String> values = {};

  /// Set to make [write] fail, as a storage error would.
  Error? failWrites;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    final fail = failWrites;
    if (fail != null) throw fail;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<int>> wrapKey(List<int> key, {required bool requireBiometry}) =>
      throw UnimplementedError();

  @override
  Future<List<int>> unwrapKey(List<int> wrapped, {required String reason}) =>
      throw UnimplementedError();
}

/// The PIN token worked out in place: tests do not wait for an isolate to
/// start, so how busy the machine is does not change the outcome.
Future<Uint8List> inlinePinToken(
  String pin,
  Uint8List salt,
  int iterations,
) async => pbkdf2Sha256(utf8.encode(pin), salt, iterations);
