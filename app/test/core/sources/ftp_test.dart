import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/ftp/ftp_file_system.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/source_builders.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'ftp_server.dart';

final class _Hosts implements NetworkPolicy {
  _Hosts(this.hosts);

  final Set<String> hosts;

  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => hosts.contains(host);

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}

int seedByte(int i) => (i * 131 + 7) & 0xff;

void main() {
  late Directory root;
  late Directory certs;
  SecurityContext? tls;
  final lan = _Hosts({'127.0.0.1'});

  setUpAll(() async {
    certs = await Directory.systemTemp.createTemp('mediahro_ftp_cert');
    tls = await testTlsContext(certs);
  });
  tearDownAll(() => certs.delete(recursive: true));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mediahro_ftp');
    Directory('${root.path}/Films').createSync();
    File('${root.path}/Films/movie.mkv')
        .writeAsBytesSync([for (var i = 0; i < (3 << 20); i++) seedByte(i)]);
    File('${root.path}/Films/movie.en.srt')
        .writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nHi\n');
    File('${root.path}/readme.txt').writeAsStringSync('hello');
  });
  tearDown(() => root.delete(recursive: true));

  Uri at(TestFtpServer s, String path, {String scheme = 'ftp'}) =>
      Uri(scheme: scheme, host: '127.0.0.1', port: s.port, path: path);

  Future<void> contract(
    FtpFileSystem fs,
    TestFtpServer s, {
    String scheme = 'ftp',
  }) async {
    final top = await fs.list(at(s, '/', scheme: scheme)).toList();
    expect(
      {for (final e in top) e.name: e.isDirectory},
      {'Films': true, 'readme.txt': false},
    );
    final films = top.firstWhere((e) => e.name == 'Films');
    final movie = (await fs.list(films.uri).toList()).firstWhere(
      (e) => e.name == 'movie.mkv',
    );
    expect(movie.size, 3 << 20);
    expect(movie.modified, isNotNull);
    expect((await fs.stat(movie.uri)).size, 3 << 20);
    expect((await fs.stat(films.uri)).isDirectory, isTrue);

    final f = await fs.open(movie.uri);
    expect(await f.length(), 3 << 20);
    // Sequential reads continue one transfer; the seeks restart it.
    for (final (off, n) in [
      (0, 4096),
      (4096, 65536),
      (69632, 10),
      (2 << 20, 8),
      (999, 4),
      ((3 << 20) - 4, 100),
    ]) {
      final got = await f.read(off, n);
      final want = (3 << 20) - off < n ? (3 << 20) - off : n;
      expect(got.length, want, reason: 'at $off');
      expect(got, [
        for (var i = off; i < off + want; i++) seedByte(i),
      ], reason: 'at $off');
    }
    expect(await f.read(3 << 20, 10), isEmpty);
    await f.close();

    final dir = await fs.createDirectory(
      at(s, '/', scheme: scheme),
      'Up loads',
    );
    final w = await fs.create(
      dir.replace(pathSegments: [...dir.pathSegments, 'note.txt']),
    );
    await w.write(utf8.encode('ftp '));
    await w.write(utf8.encode('upload'));
    await w.close();
    expect(
      File('${root.path}/Up loads/note.txt').readAsStringSync(),
      'ftp upload',
    );

    final renamed = await fs.rename(w.uri, 'note2.txt');
    await expectLater(
      fs.rename(at(s, '/readme.txt', scheme: scheme), 'Films'),
      throwsA(isA<VirtualFileException>()),
    );
    final moved = await fs.move(renamed, films.uri);
    expect(File('${root.path}/Films/note2.txt').existsSync(), isTrue);
    expect(moved.pathSegments.last, 'note2.txt');
    await expectLater(
      fs.createDirectory(at(s, '/', scheme: scheme), 'Films'),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.alreadyExists,
        ),
      ),
    );
    await fs.delete(films.uri, recursive: true);
    expect(Directory('${root.path}/Films').existsSync(), isFalse);
    await expectLater(
      fs.stat(movie.uri),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.notFound,
        ),
      ),
    );
    await fs.close();
  }

  test('NET-004 FTP with MLSD/EPSV: list, stat, ranged reads, upload, rename, move, delete', () async {
    final s = await TestFtpServer.start(root);
    addTearDown(s.close);
    await contract(
      FtpFileSystem(
        FtpOptions(
          host: '127.0.0.1',
          port: s.port,
          user: 'test',
          password: 'testpass',
        ),
        lan,
      ),
      s,
    );
    expect(s.commands, contains(startsWith('MLSD')));
    expect(s.commands, contains('PASS ***'));
  });

  test('NET-004 FTP without MLSD or EPSV falls back to LIST, SIZE/MDTM and PASV (ignoring its address)', () async {
    final s = await TestFtpServer.start(
      root,
      options: const TestFtpOptions(mlsd: false, epsv: false),
    );
    addTearDown(s.close);
    await contract(
      FtpFileSystem(
        FtpOptions(
          host: '127.0.0.1',
          port: s.port,
          user: 'test',
          password: 'testpass',
        ),
        lan,
      ),
      s,
    );
    expect(s.commands, contains('LIST'));
    expect(s.commands, isNot(contains(startsWith('MLSD'))));
  });

  test('NET-004 explicit FTPS: untrusted certificate reports its fingerprint, the pinned one works over PROT P', () async {
    final ctx = tls;
    if (ctx == null) return markTestSkipped('openssl not installed');
    final s = await TestFtpServer.start(
      root,
      options: TestFtpOptions(context: ctx, requireTls: true),
    );
    addTearDown(s.close);
    String? fp;
    try {
      await FtpFileSystem(
        FtpOptions(
          host: '127.0.0.1',
          port: s.port,
          security: FtpSecurity.explicit,
          user: 'test',
          password: 'testpass',
        ),
        lan,
      ).list(at(s, '/', scheme: 'ftpes')).toList();
      fail('expected an untrusted certificate');
    } on VirtualFileException catch (e) {
      expect(e.error, VirtualFileError.untrustedCertificate);
      fp = e.detail;
    }
    expect(fp, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    expect(
      s.commands,
      isNot(contains('PASS ***')),
      reason: 'no password before TLS',
    );
    await contract(
      FtpFileSystem(
        FtpOptions(
          host: '127.0.0.1',
          port: s.port,
          security: FtpSecurity.explicit,
          user: 'test',
          password: 'testpass',
          certSha256: fp,
        ),
        lan,
      ),
      s,
      scheme: 'ftpes',
    );
    expect(
      s.commands,
      containsAllInOrder([
        'AUTH TLS',
        'USER test',
        'PASS ***',
        'PBSZ 0',
        'PROT P',
      ]),
    );
  });

  test('NET-004 implicit FTPS on its own port', () async {
    final ctx = tls;
    if (ctx == null) return markTestSkipped('openssl not installed');
    final s = await TestFtpServer.start(
      root,
      options: TestFtpOptions(context: ctx, implicitTls: true),
    );
    addTearDown(s.close);
    final probe = FtpFileSystem(
      FtpOptions(
        host: '127.0.0.1',
        port: s.port,
        security: FtpSecurity.implicit,
        user: 'test',
        password: 'testpass',
      ),
      lan,
    );
    final fp = await probe
        .stat(at(s, '/readme.txt', scheme: 'ftps'))
        .then<String?>(
          (_) => null,
          onError: (Object e) => (e as VirtualFileException).detail,
        );
    expect(fp, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    await contract(
      FtpFileSystem(
        FtpOptions(
          host: '127.0.0.1',
          port: s.port,
          security: FtpSecurity.implicit,
          user: 'test',
          password: 'testpass',
          certSha256: fp,
        ),
        lan,
      ),
      s,
      scheme: 'ftps',
    );
  });

  test('NET-004 wrong password, unconfigured host and injected newlines are refused', () async {
    final s = await TestFtpServer.start(root);
    addTearDown(s.close);
    await expectLater(
      FtpFileSystem(
        FtpOptions(
          host: '127.0.0.1',
          port: s.port,
          user: 'test',
          password: 'nope',
        ),
        lan,
      ).stat(at(s, '/readme.txt')),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.authenticationRequired,
        ),
      ),
    );
    await expectLater(
      FtpFileSystem(
        FtpOptions(host: '127.0.0.1', port: s.port),
        _Hosts({}),
      ).stat(at(s, '/readme.txt')),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.permissionDenied,
        ),
      ),
    );
    final fs = FtpFileSystem(
      FtpOptions(
        host: '127.0.0.1',
        port: s.port,
        user: 'test',
        password: 'testpass',
      ),
      lan,
    );
    await expectLater(
      fs.stat(at(s, '/readme.txt\r\nDELE readme.txt')),
      throwsA(isA<VirtualFileException>()),
    );
    await expectLater(
      fs.rename(at(s, '/readme.txt'), 'x\r\nDELE y'),
      throwsA(isA<VirtualFileException>()),
    );
    expect(File('${root.path}/readme.txt').existsSync(), isTrue);
    expect(s.commands.where((c) => c.startsWith('DELE')), isEmpty);
    await fs.close();
  });

  test('NET-004 an aborted upload removes the partial file', () async {
    final s = await TestFtpServer.start(root);
    addTearDown(s.close);
    final fs = FtpFileSystem(
      FtpOptions(
        host: '127.0.0.1',
        port: s.port,
        user: 'test',
        password: 'testpass',
      ),
      lan,
    );
    final w = await fs.create(at(s, '/partial.bin'));
    await w.write(List.filled(1000, 1));
    await w.abort();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(File('${root.path}/partial.bin').existsSync(), isFalse);
  });

  test('NET-004 Apple builders use the Dart FTP/FTPS client; SFTP reports unsupported', () async {
    final b = defaultFileSystemBuilders(nativeCurl: false);
    final s = await TestFtpServer.start(root);
    addTearDown(s.close);
    final fs = b[SourceKind.ftp]!(
      SourceSpec(
        kind: SourceKind.ftp,
        root: at(s, '/'),
        userName: 'test',
        secret: 'testpass',
      ),
    );
    expect(fs, isA<FtpFileSystem>());
    expect(fs.schemes, contains('ftps'));
    // The builder's policy allows exactly the source's host.
    expect((await fs.stat(at(s, '/readme.txt'))).size, 5);
    await (fs as FtpFileSystem).close();
    final secure = b[SourceKind.ftp]!(
      SourceSpec(
        kind: SourceKind.ftp,
        root: Uri.parse('ftps://nas.local/'),
        options: const {'certSha256': 'AA'},
      ),
    ) as FtpFileSystem;
    expect(secure.options.security, FtpSecurity.implicit);
    expect(secure.options.certSha256, 'AA');
    expect(
      () => b[SourceKind.sftp]!(
        SourceSpec(kind: SourceKind.sftp, root: Uri.parse('sftp://nas.local/')),
      ),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.unsupported,
        ),
      ),
    );
  });
}
