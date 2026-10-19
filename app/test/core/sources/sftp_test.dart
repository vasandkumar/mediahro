import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/sources/sftp/sftp_file_system.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'sftp_fakes.dart';

void main() {
  late FakeSftp server;
  Uri u(String p) => Uri(scheme: 'sftp', host: 'nas', path: p);
  SftpEndpoint ep({String? known}) => SftpEndpoint(
    host: 'nas',
    username: 'me',
    passwordSecretRef: 'source.1/password',
    knownHostKeySha256: known,
  );

  setUp(() {
    server = FakeSftp()
      ..secrets['source.1/password'] = 'pw'
      ..file('/media/Films/movie.mkv', List.generate(100000, (i) => i % 251))
      ..file('/media/readme.txt', [104, 105]);
  });

  test(
    'NET-004 SFTP: the first connection reports the host key and reads nothing',
    () async {
      final fs = SftpFileSystem(server, ep());
      await expectLater(
        fs.list(u('/media')).toList(),
        throwsA(
          isA<VirtualFileException>()
              .having(
                (e) => e.error,
                'error',
                VirtualFileError.untrustedCertificate,
              )
              .having((e) => e.detail, 'detail', 'SHA256:aaaa'),
        ),
      );
      expect(server.open, 0, reason: 'the session is closed again');
    },
  );

  test(
    'NET-004 SFTP: a changed host key is refused even after trust',
    () async {
      server.hostKey = 'SHA256:evil';
      await expectLater(
        SftpFileSystem(
          server,
          ep(known: 'SHA256:aaaa'),
        ).stat(u('/media/readme.txt')),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.detail,
            'detail',
            'SHA256:evil',
          ),
        ),
      );
    },
  );

  test('NET-004 SFTP: list, stat, random-access reads, rename, move and recursive delete', () async {
    final fs = SftpFileSystem(server, ep(known: 'SHA256:aaaa'));
    final top = await fs.list(u('/media')).toList();
    expect(
      {for (final e in top) e.name: e.isDirectory},
      {'Films': true, 'readme.txt': false},
    );
    final movie =
        (await fs.list(top.firstWhere((e) => e.name == 'Films').uri).toList())
            .single;
    expect(movie.uri, u('/media/Films/movie.mkv'));
    expect(movie.size, 100000);
    final f = await fs.open(movie.uri);
    expect(await f.read(99998, 10), [99998 % 251, 99999 % 251]);
    expect(await f.read(100000, 10), isEmpty);
    expect(await f.read(500, 3), [500 % 251, 501 % 251, 502 % 251]);
    await f.close();
    expect(
      server.connects.single.passwordSecretRef,
      'source.1/password',
      reason: 'refs, never values',
    );

    await expectLater(
      fs.rename(u('/media/readme.txt'), 'Films'),
      throwsA(isA<VirtualFileException>()),
    );
    final r = await fs.rename(u('/media/readme.txt'), 'notes.txt');
    expect(r, u('/media/notes.txt'));
    await fs.move(r, u('/media/Films'));
    expect(server.tree.containsKey('/media/Films/notes.txt'), isTrue);
    await fs.delete(u('/media/Films'), recursive: true);
    expect(
      server.tree.keys.where((k) => k.startsWith('/media/Films')),
      isEmpty,
    );
    final dir = await fs.createDirectory(u('/media'), 'Up');
    expect(dir, u('/media/Up'));
    await expectLater(
      fs.createDirectory(u('/media'), 'Up'),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.alreadyExists,
        ),
      ),
    );
    final w = await fs.create(u('/media/Up/note.txt'));
    await w.write([1, 2]);
    await w.write([3]);
    await w.close();
    expect(server.tree['/media/Up/note.txt'], [1, 2, 3]);
    await expectLater(
      fs.create(u('/media/Up/note.txt')),
      throwsA(isA<VirtualFileException>()),
    );
    final partial = await fs.create(u('/media/Up/partial.bin'));
    await partial.write([9]);
    await partial.abort();
    expect(server.tree.containsKey('/media/Up/partial.bin'), isFalse);
    await fs.close();
    expect(server.open, 0);
  });

  test(
    'NET-004 SFTP: a refused login maps to an error and leaves no session',
    () async {
      server.secrets['source.1/password'] = 'wrong';
      await expectLater(
        SftpFileSystem(
          server,
          ep(known: 'SHA256:aaaa'),
        ).stat(u('/media/readme.txt')),
        throwsA(isA<VirtualFileException>()),
      );
      expect(server.open, 0);
    },
  );
}
