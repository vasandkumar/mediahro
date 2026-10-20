import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_tls.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: TlsSocketFacade and TlsServerFacade on an Android device, all
/// on 127.0.0.1. A debug-only hook (`mediahro.test/tls`) runs a self-signed
/// TLS echo server and an FTPS-style `AUTH TLS` server; the mutual-TLS tests
/// use the facade's own listener with Keystore identities.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;
  const localhost = '127.0.0.1';

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/tls',
    StandardMessageCodec(),
  );
  late Map<Object?, Object?> server;
  late AndroidTlsSocketFacade tls;

  setUp(() async {
    if (!android) return;
    tls = AndroidTlsSocketFacade();
    server = (await hook.send(['start']))! as Map<Object?, Object?>;
  });
  tearDown(() async {
    if (android) await hook.send(['stop']);
  });

  String sha() => server['sha256']! as String;
  int tlsPort() => server['tlsPort']! as int;

  /// Reads from [input] until [n] bytes arrived.
  Future<String> readText(StreamIterator<List<int>> input, int n) async {
    final out = <int>[];
    while (out.length < n && await input.moveNext()) {
      out.addAll(input.current);
    }
    return utf8.decode(out);
  }

  Future<String> echo(TlsSocket s, String text) async {
    final it = StreamIterator<List<int>>(s.input);
    await s.write(utf8.encode(text));
    return await readText(
      it,
      utf8.encode(text).length,
    ).timeout(const Duration(seconds: 10));
  }

  testWidgets('NET-004 Android bindings provide the TLS facades', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(tlsSocketProvider), isA<AndroidTlsSocketFacade>());
    expect(c.read(tlsServerProvider), isA<AndroidTlsServerFacade>());
  }, skip: !android);

  testWidgets(
    'NET-004 an unpinned self-signed server is UntrustedCertificate with its fingerprint',
    (tester) async {
      await expectLater(
        tls.connect(localhost, tlsPort()),
        throwsA(
          isA<UntrustedCertificate>()
              .having((e) => e.sha256, 'sha256', sha())
              .having((e) => e.host, 'host', localhost),
        ),
      );
    },
    skip: !android,
  );

  testWidgets('NET-004 a pinned server: TLS 1.2 or newer, data both ways', (
    tester,
  ) async {
    // Lower-case without colons is accepted as the same pin.
    final pin = sha().replaceAll(':', '').toLowerCase();
    final s = await tls.connect(localhost, tlsPort(), pinnedSha256: pin);
    addTearDown(s.close);
    expect(s.isTls, isTrue);
    expect(['TLSv1.2', 'TLSv1.3'], contains(s.protocolVersion));
    expect(s.peerCertificateSha256, sha());
    expect(await echo(s, 'hello over TLS'), 'hello over TLS');
  }, skip: !android);

  testWidgets(
    'NET-004 explicit AUTH TLS upgrades a plain connection in place',
    (tester) async {
      final plain = await tls.connectPlain(
        localhost,
        server['starttlsPort']! as int,
      );
      expect(plain.isTls, isFalse);
      expect(plain.protocolVersion, isEmpty);
      final it = StreamIterator<List<int>>(plain.input);
      await plain.write(utf8.encode('AUTH TLS\r\n'));
      expect(await readText(it, 4), startsWith('234'));
      final secure = await tls.upgrade(plain.id, pinnedSha256: sha());
      addTearDown(secure.close);
      expect(secure.isTls, isTrue);
      expect(secure.peerCertificateSha256, sha());
      expect(await echo(secure, 'after AUTH TLS'), 'after AUTH TLS');
    },
    skip: !android,
  );

  testWidgets('NET-004 a data channel resumes the control session', (
    tester,
  ) async {
    final control = await tls.connect(
      localhost,
      tlsPort(),
      pinnedSha256: sha(),
    );
    addTearDown(control.close);
    final data = await tls.connect(
      localhost,
      tlsPort(),
      pinnedSha256: sha(),
      resumeSessionOf: control.id,
    );
    addTearDown(data.close);
    expect(data.isTls, isTrue);
    expect(await echo(data, 'data channel'), 'data channel');
    if (control.protocolVersion == 'TLSv1.2') {
      final ids = ((await hook.send(['sessions']))! as List<Object?>)
          .cast<String>();
      expect(ids.length, greaterThanOrEqualTo(2));
      expect(ids.last, ids[ids.length - 2], reason: 'session resumed');
    }
  }, skip: !android);

  testWidgets(
    'NET-017 mutual TLS: paired peers connect, unpaired ones are refused',
    (tester) async {
      final server = AndroidTlsServerFacade();
      final a = await server.identity('c4a-test-a');
      final b = await server.identity('c4a-test-b');
      final c = await server.identity('c4a-test-c');
      expect(a.certificateSha256, isNot(b.certificateSha256));
      expect(
        (await server.identity('c4a-test-a')).certificateSha256,
        a.certificateSha256,
        reason: 'the identity persists',
      );

      final listener = await server.listen(
        a,
        trustedPeers: {b.certificateSha256},
      );
      addTearDown(listener.close);
      final accepted = StreamIterator(listener.connections);

      final client = await server.connectMutual(
        localhost,
        listener.port,
        identity: b,
        peerSha256: a.certificateSha256,
      );
      addTearDown(client.close);
      expect(client.peerCertificateSha256, a.certificateSha256);
      expect(
        await accepted.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      final peer = accepted.current;
      addTearDown(peer.close);
      expect(peer.peerCertificateSha256, b.certificateSha256);
      final it = StreamIterator<List<int>>(peer.input);
      await client.write(utf8.encode('paired'));
      expect(
        await readText(it, 6).timeout(const Duration(seconds: 10)),
        'paired',
      );

      // Not paired: refused in the handshake.
      await expectLater(
        server.connectMutual(
          localhost,
          listener.port,
          identity: c,
          peerSha256: a.certificateSha256,
        ),
        throwsA(isA<PlatformException>()),
      );
      // The client pins the server too.
      await expectLater(
        server.connectMutual(
          localhost,
          listener.port,
          identity: b,
          peerSha256: c.certificateSha256,
        ),
        throwsA(isA<PlatformException>()),
      );
      // Pairing C later lets it in.
      await listener.setTrustedPeers({
        b.certificateSha256,
        c.certificateSha256,
      });
      final late = await server.connectMutual(
        localhost,
        listener.port,
        identity: c,
        peerSha256: a.certificateSha256,
      );
      addTearDown(late.close);
      expect(late.isTls, isTrue);
    },
    skip: !android,
  );
}
