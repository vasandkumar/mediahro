import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_security.dart';
import 'package:mediahro/platform/android/android_sftp.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: SftpFacade on an Android device against a debug-only Apache
/// MINA SSHD server on 127.0.0.1 (`mediahro.test/sftp`). Secrets go into
/// the real secure storage and only their references reach the facade.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;
  const localhost = '127.0.0.1';

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/sftp',
    StandardMessageCodec(),
  );
  late Map<Object?, Object?> server;
  late AndroidSftp sftp;
  final secure = AndroidSecureStorage();
  final run = DateTime.now().microsecondsSinceEpoch;
  final passwordRef = 'c4a.sftp.$run/password';
  final keyRef = 'c4a.sftp.$run/privateKey';

  setUp(() async {
    if (!android) return;
    sftp = AndroidSftp();
    server = (await hook.send(['start']))! as Map<Object?, Object?>;
    expect(server['error'], isNull, reason: '$server');
    await secure.write(passwordRef, server['password']! as String);
    await secure.write(keyRef, server['keyPem']! as String);
  });
  tearDown(() async {
    if (!android) return;
    await hook.send(['stop']);
    await secure.delete(passwordRef);
    await secure.delete(keyRef);
  });

  int port() => server['port']! as int;
  String hostKey() => server['hostKeySha256']! as String;
  Future<int> attempts() async => (await hook.send(['authAttempts']))! as int;

  SftpEndpoint endpoint({String? known, bool key = false}) => SftpEndpoint(
    host: localhost,
    port: port(),
    username: 'test',
    passwordSecretRef: key ? null : passwordRef,
    privateKeySecretRef: key ? keyRef : null,
    knownHostKeySha256: known,
  );

  testWidgets('NET-004 Android bindings provide SFTP', (tester) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(sftpProvider), isA<AndroidSftp>());
  }, skip: !android);

  testWidgets(
    'NET-004 first contact reports the host key and sends no credentials',
    (tester) async {
      final s = await sftp.connect(endpoint());
      expect(s.hostKeySha256, hostKey());
      await expectLater(
        s.list('/'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'notAuthenticated',
          ),
        ),
      );
      await s.close();
      expect(await attempts(), 0);
    },
    skip: !android,
  );

  testWidgets('NET-004 a changed host key also stops before login', (
    tester,
  ) async {
    final s = await sftp.connect(endpoint(known: 'AA:BB:CC'));
    expect(s.hostKeySha256, hostKey());
    await s.close();
    expect(await attempts(), 0);
  }, skip: !android);

  testWidgets(
    'NET-004 password login: list, stat, ranged reads, write, rename, mkdir, delete',
    (tester) async {
      // Lower case without colons is the same confirmed key.
      final known = hostKey().replaceAll(':', '').toLowerCase();
      final s = await sftp.connect(endpoint(known: known));
      addTearDown(s.close);
      expect(
        (await s.list('/')).map((e) => e.path.split('/').last),
        contains('Films'),
      );
      final films = await s.list('/Films');
      final clip = films.singleWhere((e) => e.path.endsWith('clip.bin'));
      expect(clip.isDirectory, isFalse);
      expect(clip.size, 100000);
      expect((await s.stat('/Films')).isDirectory, isTrue);

      final head = await s.read('/Films/clip.bin', 0, 16);
      expect(head, List.generate(16, (i) => i % 251));
      final mid = await s.read('/Films/clip.bin', 60000, 1000);
      expect(mid, List.generate(1000, (i) => (60000 + i) % 251));
      final tail = await s.read('/Films/clip.bin', 99990, 100);
      expect(tail.length, 10, reason: 'short read at end of file');

      await s.mkdir('/New');
      final sink = await s.openWrite('/New/a.txt');
      await sink.write(utf8.encode('hello '));
      await sink.write(utf8.encode('sftp'));
      await sink.close();
      expect(utf8.decode(await s.read('/New/a.txt', 0, 64)), 'hello sftp');

      final append = await s.openWrite('/New/a.txt', truncate: false);
      await append.write(utf8.encode('!'));
      await append.close();
      expect(utf8.decode(await s.read('/New/a.txt', 0, 64)), 'hello sftp!');

      final aborted = await s.openWrite('/New/partial.bin');
      await aborted.write(utf8.encode('x'));
      await aborted.abort();
      expect(
        (await s.list('/New')).map((e) => e.path.split('/').last),
        isNot(contains('partial.bin')),
      );

      await s.rename('/New/a.txt', '/New/b.txt');
      expect((await s.stat('/New/b.txt')).size, 11);
      await s.delete('/New/b.txt');
      await s.delete('/New');
      await expectLater(s.stat('/New'), throwsA(isA<PathNotFoundException>()));
    },
    skip: !android,
  );

  testWidgets('NET-004 key login with a PKCS#8 key from secure storage', (
    tester,
  ) async {
    final s = await sftp.connect(endpoint(known: hostKey(), key: true));
    addTearDown(s.close);
    expect((await s.list('/')).isNotEmpty, isTrue);
  }, skip: !android);

  testWidgets('NET-004 a wrong password is authFailed', (tester) async {
    await secure.write(passwordRef, 'wrong');
    await expectLater(
      sftp.connect(endpoint(known: hostKey())),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'authFailed'),
      ),
    );
  }, skip: !android);

  testWidgets('NET-004 an unreachable host is a SocketException', (
    tester,
  ) async {
    await expectLater(
      sftp.connect(
        const SftpEndpoint(host: localhost, port: 1, username: 'test'),
      ),
      throwsA(isA<SocketException>()),
    );
  }, skip: !android);
}
