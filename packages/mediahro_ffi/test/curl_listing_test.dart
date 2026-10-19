import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 12);

  test('NET-004 Unix LIST and SFTP long listings', () {
    final e = parseListing(
      'total 12\r\n'
      'drwxr-xr-x    2 ftp      ftp          4096 Oct 18 21:04 Films\r\n'
      '-rw-r--r--    1 ftp      ftp      7340032000 Jan  5  2024 Big Movie (2023).mkv\r\n'
      '-rw-r--r--    1 1000     1000            12 Dec 31 23:59 new year.txt\r\n'
      'lrwxrwxrwx    1 ftp      ftp             5 Oct 01 10:00 latest -> Films\r\n'
      '-rw-r--r--    1 owner group 3 Oct 19 09:30 . \r\n'
      'garbage line\r\n',
      now: now,
    );
    expect(e.map((x) => x.name), [
      'Films',
      'Big Movie (2023).mkv',
      'new year.txt',
      'latest',
    ]);
    expect(e[0].isDirectory, isTrue);
    expect(e[0].modified, DateTime.utc(2026, 10, 18, 21, 4));
    expect(e[1].size, 7340032000, reason: 'large files');
    expect(e[1].modified, DateTime.utc(2024, 1, 5));
    expect(
      e[2].modified,
      DateTime.utc(2025, 12, 31, 23, 59),
      reason: 'future date means last year',
    );
    expect(e[3].linkTarget, 'Films');
  });

  test('NET-004 MS-DOS (IIS) listings', () {
    final e = parseListing(
      '10-19-26  10:05AM       <DIR>          Music\r\n'
      '10-19-26  01:30PM               2048 song one.flac\r\n',
      now: now,
    );
    expect(e.first.isDirectory, isTrue);
    expect(e.last.name, 'song one.flac');
    expect(e.last.size, 2048);
    expect(e.last.modified, DateTime.utc(2026, 10, 19, 13, 30));
  });

  test('NET-004 SFTP host key fingerprints use SHA-256', () {
    expect(
      base64.encode(sha256ForTesting(Uint8List.fromList(utf8.encode('abc')))),
      'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=',
    );
    expect(sha256ForTesting(Uint8List(0)).first, 0xe3);
    final long = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    expect(sha256ForTesting(long), hasLength(32));
  });
}
