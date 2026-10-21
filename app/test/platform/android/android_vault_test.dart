import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_vault.dart';
import 'package:mediahro/platform/android/gen/vault_api.pigeon.dart';
import 'package:mediahro/platform/vault_crypto.dart';

/// The Dart half of lane C4a's vault crypto and secure window (ADR-039).
final class _FakeCrypto extends VaultCryptoHostApi {
  PlatformException? failure;
  final calls = <String>[];

  void _fail() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<int> openMasterKey(bool requireBiometry) async {
    calls.add('open:$requireBiometry');
    _fail();
    return 7;
  }

  @override
  Future<Uint8List> newFileKey(int handle) async =>
      Uint8List.fromList([1, handle]);

  @override
  Future<void> adoptFileKey(int handle, Uint8List wrapped) async {
    calls.add('adopt:$handle:${wrapped.length}');
    _fail();
  }

  @override
  Future<Uint8List> seal(
    int handle,
    Uint8List wrapped,
    Uint8List nonce,
    Uint8List aad,
    Uint8List plaintext,
  ) async {
    _fail();
    return Uint8List.fromList([...plaintext, 0]);
  }

  @override
  Future<Uint8List> open(
    int handle,
    Uint8List wrapped,
    Uint8List nonce,
    Uint8List aad,
    Uint8List sealed,
  ) async {
    _fail();
    return Uint8List.fromList(sealed.sublist(0, sealed.length - 1));
  }

  @override
  Future<void> close(int handle) async => calls.add('close:$handle');

  @override
  Future<void> reset() async => calls.add('reset');
}

final class _FakeWindow extends SecureWindowHostApi {
  final calls = <bool>[];

  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

void main() {
  late _FakeCrypto api;
  late AndroidVaultCrypto crypto;
  setUp(() {
    api = _FakeCrypto();
    crypto = AndroidVaultCrypto(api: api);
  });

  test('IMG-011 handles, file keys and a seal and open round trip', () async {
    final master = await crypto.openMasterKey(requireBiometry: true);
    expect(master, const VaultKeyHandle(7));
    final key = await crypto.newFileKey(master);
    expect(key.master, master);
    final adopted = await crypto.adoptFileKey(master, key.bytes);
    expect(adopted.bytes, key.bytes);
    final nonce = Uint8List(VaultCryptoFacade.nonceLength);
    final sealed = await crypto.seal(
      key,
      nonce,
      Uint8List(0),
      Uint8List.fromList([5, 6]),
    );
    expect(
      await crypto.open(key, nonce, Uint8List(0), sealed),
      Uint8List.fromList([5, 6]),
    );
    await crypto.close(master);
    await crypto.reset();
    expect(api.calls, ['open:true', 'adopt:7:2', 'close:7', 'reset']);
  });

  test('IMG-011 every native failure code maps to its error', () async {
    for (final error in VaultCryptoError.values) {
      api.failure = PlatformException(code: error.name, message: 'native');
      await expectLater(
        crypto.openMasterKey(requireBiometry: false),
        throwsA(
          isA<VaultCryptoException>()
              .having((e) => e.error, 'error', error)
              .having((e) => e.message, 'message', 'native'),
        ),
      );
    }
  });

  test('IMG-011 an unknown native code is unavailable', () async {
    api.failure = PlatformException(code: 'weird');
    await expectLater(
      crypto.adoptFileKey(const VaultKeyHandle(1), Uint8List(3)),
      throwsA(
        isA<VaultCryptoException>().having(
          (e) => e.error,
          'error',
          VaultCryptoError.unavailable,
        ),
      ),
    );
  });

  test('IMG-011 the secure window sets the flag and reports capture', () async {
    final window = _FakeWindow();
    final events = StreamController<bool>();
    addTearDown(() => unawaited(events.close()));
    final secure = AndroidSecureWindow(
      api: window,
      events: () => events.stream,
    );
    await secure.setSecure(secure: true);
    await secure.setSecure(secure: false);
    expect(window.calls, [true, false]);
    final next = secure.captureActive.first;
    events.add(true);
    expect(await next, isTrue);
  });
}
