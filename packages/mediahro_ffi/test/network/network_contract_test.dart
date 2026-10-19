// FFI network contract tests against the docker-compose environment
// (docs/11 §2). Run with MEDIAHRO_NET_ENV=1 after seed.dart and
// `docker compose up`; skipped otherwise.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

import 'seed.dart' show seedByte;

final bool _enabled = Platform.environment['MEDIAHRO_NET_ENV'] == '1';
final String? _skip = _enabled
    ? null
    : 'blocked: STATUS §3 — network-env CI job (orchestrator); locally set '
          'MEDIAHRO_NET_ENV=1 with the docker environment running';
final String _host = Platform.environment['MEDIAHRO_NET_HOST'] ?? '127.0.0.1';
final int? _smbPort = int.tryParse(Platform.environment['SMB_PORT'] ?? '');
final String _data =
    Platform.environment['MEDIAHRO_NET_DATA'] ?? 'test/network/data';

Matcher _err(VirtualFileError e) =>
    throwsA(isA<VirtualFileException>().having((x) => x.error, 'error', e));

/// The common contract every network file system meets.
Future<void> contract(
  MutableFileSystem fs,
  Uri root, {
  bool writable = true,
  bool large = true,
}) async {
  final top = await fs.list(root).toList();
  expect(top.map((e) => e.name), containsAll(['Films', 'Music', 'Comics']));
  final films = top.firstWhere((e) => e.name == 'Films');
  expect(films.isDirectory, isTrue);
  final movies = await fs.list(films.uri).toList();
  final movie = movies.firstWhere((e) => e.name == 'Movie One (2024).mkv');
  expect(movie.size, 3 << 20);
  expect(movie.modified, isNotNull);

  final f = await fs.open(movie.uri);
  expect(await f.length(), 3 << 20);
  // Seek anywhere (NET-001 "seek"; the engine's stream protocol relies on it).
  for (final off in [0, 1, 65535, 1 << 20, (3 << 20) - 5]) {
    final got = await f.read(off, 16);
    expect(got, [
      for (var i = off; i < off + got.length; i++) seedByte(i),
    ], reason: 'offset $off');
  }
  expect(await f.read((3 << 20) - 2, 10), hasLength(2));
  await f.close();

  final unicode = await fs
      .list(top.firstWhere((e) => e.name == 'Spaces & Ünïcode').uri)
      .toList();
  expect(unicode.single.name, 'file name.txt');

  if (large) {
    final big = await fs.open(root.resolve('Large/sparse-5g.bin'));
    expect(big.isSeekable, isTrue);
    expect(await big.length(), 5 << 30);
    expect(await big.read((5 << 30) - 1, 1), [0x5A], reason: '64-bit offsets');
    await big.close();
  }

  await expectLater(
    fs.open(root.resolve('Films/nope.mkv')),
    _err(VirtualFileError.notFound),
  );

  if (writable) {
    final dir = await fs.createDirectory(
      root,
      'mediahro-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    final w = await fs.create(dir.resolve('upload.bin'));
    await w.write(utf8.encode('hello '));
    await w.write(utf8.encode('network'));
    await w.close();
    final back = await fs.open(dir.resolve('upload.bin'));
    expect(utf8.decode(await back.read(0, 100)), 'hello network');
    await back.close();
    final renamed = await fs.rename(dir.resolve('upload.bin'), 'renamed.bin');
    expect((await fs.list(dir).toList()).map((e) => e.name), ['renamed.bin']);
    await fs.delete(renamed);
    await fs.delete(dir, recursive: true);
  }
}

void main() {
  group('NET-001 SMB2/3', () {
    Uri root(String share) =>
        Uri(scheme: 'smb', host: _host, port: _smbPort, path: '/$share/');

    test('user login: list, seek, large files, unicode, writes', () async {
      final fs = smbFileSystem(
        root('media'),
        SmbOptions(
          server: _host,
          port: _smbPort,
          share: 'media',
          user: 'test',
          password: 'testpass',
        ),
      );
      addTearDown(fs.close);
      await contract(fs, root('media'));
    });

    test('guest access to a public share', () async {
      final fs = smbFileSystem(
        root('public'),
        SmbOptions(server: _host, port: _smbPort, share: 'public', guest: true),
      );
      addTearDown(fs.close);
      await contract(fs, root('public'), writable: false);
    });

    test('SMB3 encryption (seal) and signing', () async {
      final fs = smbFileSystem(
        root('secure'),
        SmbOptions(
          server: _host,
          port: _smbPort,
          share: 'secure',
          user: 'test',
          password: 'testpass',
          version: SmbVersion.smb3,
          encrypt: true,
          sign: true,
        ),
      );
      addTearDown(fs.close);
      expect(
        (await fs.list(root('secure')).toList()).map((e) => e.name),
        contains('Films'),
      );
    });

    test('wrong password maps to authenticationRequired', () async {
      final fs = smbFileSystem(
        root('media'),
        SmbOptions(
          server: _host,
          port: _smbPort,
          share: 'media',
          user: 'test',
          password: 'wrong',
        ),
      );
      addTearDown(fs.close);
      await expectLater(
        fs.list(root('media')).toList(),
        _err(VirtualFileError.authenticationRequired),
      );
    });

    test('DFS link resolves to its target share', () async {
      final fs = smbFileSystem(
        root('dfs'),
        SmbOptions(server: _host, port: _smbPort, share: 'dfs', guest: true),
      );
      addTearDown(fs.close);
      final linked = await fs.list(root('dfs').resolve('linked/')).toList();
      expect(linked.map((e) => e.name), contains('Films'));
    });

    test(
      'FILE-004 archive on the share is browsed without copying',
      () async {
        final opts = SmbOptions(
          server: _host,
          port: _smbPort,
          share: 'media',
          user: 'test',
          password: 'testpass',
        );
        final arch = archiveFileSystem(
          Uri.parse('archive:///'),
          SyncArchiveSource(
            () => Smb2SyncFileSystem(opts),
            'Comics/issue 1.cbz',
          ),
        );
        addTearDown(arch.close);
        final pages = await arch.list(Uri.parse('archive:///')).toList();
        expect(pages.map((e) => e.name).toSet(), {
          'page 01.jpg',
          'page 02.jpg',
        });
        final p = await arch.open(Uri.parse('archive:///page%2001.jpg'));
        expect(await p.read(10, 3), [seedByte(10), seedByte(11), seedByte(12)]);
      },
      skip: NativeLibraries.isAvailable(NativeLibrary.archive) ? null : 'blocked: STATUS §3 — mediahro-deps libarchive for this platform (B4)',
    );
  }, skip: _skip);

  group('NET-002 NFS', () {
    final export = Platform.environment['NFS_EXPORT'] ?? '/srv/nfs';

    test('NFSv3 mount', () async {
      final root = Uri(scheme: 'nfs', host: _host, path: '$export/');
      final fs = nfsFileSystem(root, NfsOptions(server: _host, export: export));
      addTearDown(fs.close);
      await contract(fs, root);
    });

    test('NFSv4 mount', () async {
      final root = Uri(scheme: 'nfs', host: _host, path: '/');
      final fs = nfsFileSystem(
        root,
        NfsOptions(server: _host, export: '/', version: 4),
      );
      addTearDown(fs.close);
      await contract(fs, root, writable: false);
    });

    test('discovered mounts: export list of the server', () async {
      final host = _host;
      final exports = await Isolate.run(() => nfsExports(host));
      expect(exports, contains(export));
    });
  }, skip: _skip);

  group('NET-004 FTP/FTPS/SFTP', () {
    Uri root(String scheme, [int? port]) =>
        Uri(scheme: scheme, host: _host, port: port, path: '/');

    test('plain FTP', () async {
      final fs = curlFileSystem(
        root('ftp'),
        CurlOptions(
          protocol: CurlProtocol.ftp,
          host: _host,
          user: 'test',
          password: 'testpass',
        ),
      );
      addTearDown(fs.close);
      await contract(fs, root('ftp'));
    });

    test(
      'explicit FTPS (AUTH TLS) with an accepted self-signed certificate',
      () async {
        final fs = curlFileSystem(
          root('ftp'),
          CurlOptions(
            protocol: CurlProtocol.ftpes,
            host: _host,
            user: 'test',
            password: 'testpass',
            allowUntrustedTls: true,
          ),
        );
        addTearDown(fs.close);
        await contract(fs, root('ftp'), large: false);
      },
    );

    test(
      'FTPS refuses an untrusted certificate until the user accepts it',
      () async {
        final fs = curlFileSystem(
          root('ftp'),
          CurlOptions(
            protocol: CurlProtocol.ftpes,
            host: _host,
            user: 'test',
            password: 'testpass',
          ),
        );
        addTearDown(fs.close);
        await expectLater(
          fs.list(root('ftp')).toList(),
          _err(VirtualFileError.untrustedCertificate),
        );
      },
    );

    test('implicit FTPS', () async {
      final fs = curlFileSystem(
        root('ftps', 990),
        CurlOptions(
          protocol: CurlProtocol.ftps,
          host: _host,
          port: 990,
          user: 'test',
          password: 'testpass',
          allowUntrustedTls: true,
        ),
      );
      addTearDown(fs.close);
      await contract(fs, root('ftps', 990), large: false, writable: false);
    });

    test('SFTP host key is trusted on first use, then pinned; password and key auth', () async {
      final r = root('sftp', 2222);
      final first = curlFileSystem(
        r,
        CurlOptions(
          protocol: CurlProtocol.sftp,
          host: _host,
          port: 2222,
          rootPath: '/srv/media',
          user: 'test',
          password: 'testpass',
        ),
      );
      String? fingerprint;
      try {
        await first.list(r).toList();
      } on VirtualFileException catch (e) {
        expect(e.error, VirtualFileError.untrustedCertificate);
        fingerprint = e.detail;
      } finally {
        await first.close();
      }
      expect(fingerprint, isNotNull);
      final pw = curlFileSystem(
        r,
        CurlOptions(
          protocol: CurlProtocol.sftp,
          host: _host,
          port: 2222,
          rootPath: '/srv/media',
          user: 'test',
          password: 'testpass',
          hostKeySha256: fingerprint,
        ),
      );
      addTearDown(pw.close);
      await contract(pw, r);
      final key = File('$_data/ssh/id_ed25519').readAsStringSync();
      final byKey = curlFileSystem(
        r,
        CurlOptions(
          protocol: CurlProtocol.sftp,
          host: _host,
          port: 2222,
          rootPath: '/srv/media',
          user: 'test',
          privateKeyPem: key,
          hostKeySha256: fingerprint,
        ),
      );
      addTearDown(byKey.close);
      expect(
        (await byKey.list(r).toList()).map((e) => e.name),
        contains('Films'),
      );
    });
  }, skip: _skip);
}
