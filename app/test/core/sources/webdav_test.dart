import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/sources/http/http_auth.dart';
import 'package:mediahro/core/sources/http/http_file.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/core/sources/http/webdav_file_system.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'dav_server.dart';

final class _Lan implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => host == '127.0.0.1';

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}

void main() {
  late TestDavServer server;
  late NetworkGateway gw;

  tearDown(() async {
    gw.close();
    await server.close();
  });

  Future<WebDavFileSystem> connect({
    String? user,
    String? password,
    bool digest = true,
    bool insecureBasic = false,
  }) async {
    server = await TestDavServer.start(
      user: 'me',
      password: 's3cret',
      digest: digest,
    );
    gw = NetworkGateway(_Lan());
    final auth = HttpAuth(user: user, password: password)
      ..allowInsecureBasic = insecureBasic;
    return WebDavFileSystem(HttpSession(gw, auth: auth));
  }

  test('NET-003 Digest auth, PROPFIND listing and stat', () async {
    final fs = await connect(user: 'me', password: 's3cret');
    server
      ..put('Films/Movie One.mkv', List.filled(1000, 7))
      ..put('Films/Sub/x.srt', utf8.encode('1'))
      ..put('readme.txt', utf8.encode('hi'));
    final root = await fs.list(server.root).toList();
    expect(root.map((e) => (e.name, e.isDirectory)).toSet(), {
      ('Films', true),
      ('readme.txt', false),
    });
    final films = root.firstWhere((e) => e.name == 'Films');
    final inside = await fs.list(films.uri).toList();
    final movie = inside.firstWhere((e) => e.name == 'Movie One.mkv');
    expect(movie.size, 1000);
    expect(movie.modified, DateTime.utc(2026, 10, 19, 10));
    expect(movie.uri.scheme, 'dav');
    expect((await fs.stat(movie.uri)).size, 1000);
    expect(
      server.requests.where((r) => r.startsWith('PROPFIND')),
      hasLength(greaterThan(2)),
    );
  });

  test('NET-003 wrong credentials map to authenticationRequired', () async {
    final fs = await connect(user: 'me', password: 'nope');
    await expectLater(
      fs.list(server.root).toList(),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.authenticationRequired,
        ),
      ),
    );
  });

  test(
    'NET-003 Basic auth is never sent over plain HTTP without consent',
    () async {
      final fs = await connect(user: 'me', password: 's3cret', digest: false);
      await expectLater(
        fs.list(server.root).toList(),
        throwsA(isA<VirtualFileException>()),
      );
      gw.close();
      await server.close();
      final ok = await connect(
        user: 'me',
        password: 's3cret',
        digest: false,
        insecureBasic: true,
      );
      expect(await ok.list(server.root).toList(), isEmpty);
    },
  );

  test(
    'NET-003 range reads: seekable file, block cache, short read at EOF',
    () async {
      final fs = await connect(user: 'me', password: 's3cret');
      final data = Uint8List.fromList(
        List.generate(600 * 1024, (i) => i % 251),
      );
      server.put('big.bin', data);
      final f = await fs.open(server.root.resolve('big.bin'));
      expect(f.isSeekable, isTrue);
      expect(await f.length(), data.length);
      expect(await f.read(300000, 4), data.sublist(300000, 300004));
      expect(await f.read(300004, 4), data.sublist(300004, 300008));
      final before = server.rangeRequests;
      await f.read(300100, 10);
      expect(
        server.rangeRequests,
        before,
        reason: 'served from the block cache',
      );
      expect(await f.read(data.length - 2, 100), data.sublist(data.length - 2));
      expect(await f.read(data.length + 5, 10), isEmpty);
      await f.close();
    },
  );

  test(
    'FILE-002 on WebDAV: new folder, upload, rename, move, delete',
    () async {
      final fs = await connect(user: 'me', password: 's3cret');
      final dir = await fs.createDirectory(server.root, 'New Folder');
      await expectLater(
        fs.createDirectory(server.root, 'New Folder'),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.alreadyExists,
          ),
        ),
      );
      final w = await fs.create(dir.resolve('up%20load.txt'));
      await w.write(utf8.encode('hello '));
      await w.write(utf8.encode('dav'));
      await w.close();
      expect(utf8.decode(server.files['New Folder/up load.txt']!), 'hello dav');
      final renamed = await fs.rename(
        dir.resolve('up%20load.txt'),
        'final.txt',
      );
      expect(server.files.containsKey('New Folder/final.txt'), isTrue);
      server.put('Other/keep.txt', [1]);
      final moved = await fs.move(renamed, server.root.resolve('Other/'));
      expect(server.files.containsKey('Other/final.txt'), isTrue);
      await fs.delete(moved);
      expect(server.files.containsKey('Other/final.txt'), isFalse);
      await expectLater(
        fs.delete(server.root.resolve('Other/')),
        throwsA(isA<VirtualFileException>()),
        reason: 'non-empty folder without recursive',
      );
      await fs.delete(server.root.resolve('Other/'), recursive: true);
      expect(server.dirs.contains('Other'), isFalse);
    },
  );

  test('NET-006 anonymous HTTP file reads', () async {
    server = await TestDavServer.start();
    gw = NetworkGateway(_Lan());
    server.put('a.bin', [1, 2, 3]);
    final f = await HttpVirtualFile.open(
      WebDavFileSystem.wire(server.root.resolve('a.bin')),
      HttpSession(gw),
    );
    expect(await f.read(0, 3), [1, 2, 3]);
    expect(await f.read(1, 1), [2]);
  });

  test('NET-003 Digest header follows RFC 7616 for the challenge', () {
    final auth = HttpAuth(user: 'Mufasa', password: 'Circle of Life');
    expect(
      auth.challenge(
        'Digest realm="http-auth@example.org", qop="auth, auth-int", algorithm=SHA-256, '
        'nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS"',
        secure: true,
      ),
      isTrue,
    );
    final h = auth.retryHeader(
      'GET',
      Uri.parse('https://example.org/dir/index.html'),
    )!;
    expect(h, startsWith('Digest username="Mufasa"'));
    expect(h, contains('algorithm=SHA-256'));
    expect(h, contains('qop=auth'));
    expect(h, contains('nc=00000001'));
    expect(parseAuthParams(r'a=1, b="x, \"y\"", c=z'), {
      'a': '1',
      'b': 'x, "y"',
      'c': 'z',
    });
  });
}
