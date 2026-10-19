import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/sources/url_open.dart';

void main() {
  test('CORE-005 accepts every listed scheme and normalises user input', () {
    for (final u in [
      'https://example.org/v.mp4',
      'http://10.0.0.2:8080/live.m3u8',
      'https://cdn.example/manifest.mpd',
      'rtsp://cam.local:554/stream1',
      'rtmp://live.example/app/key',
      'smb://nas/share/Films',
      'nfs://nas/export',
      'ftp://nas/pub',
      'sftp://host/home',
      'davs://cloud.example/remote.php/dav/files/me/',
    ]) {
      expect(parseUserUrl(u).uri.toString(), u, reason: u);
    }
    expect(
      parseUserUrl('  example.org/live.m3u8 ').uri.toString(),
      'https://example.org/live.m3u8',
    );
    expect(
      parseUserUrl(r'\\NAS\Media\Films').uri.toString(),
      'smb://nas/Media/Films',
    );
    expect(parseUserUrl('HTTPS://Example.org/A').uri.scheme, 'https');
    expect(parseUserUrl('smb://nas/s').kind, UrlKind.share);
    expect(parseUserUrl('rtsp://cam/s').isLive, isTrue);
  });

  test(
    'NET-006 custom headers and user agent; header injection is refused',
    () {
      final u = parseUserUrl(
        'https://h/x',
        headers: {'Referer': 'https://h/'},
        userAgent: ' VLC/3 ',
      );
      expect(u.headers, {'Referer': 'https://h/'});
      expect(u.userAgent, 'VLC/3');
      expect(
        () => parseUserUrl('https://h/x', headers: {'X': 'a\r\nEvil: 1'}),
        throwsA(isA<UrlRejected>()),
      );
      expect(
        () => parseUserUrl('https://h/x', headers: {'Bad Name': '1'}),
        throwsA(isA<UrlRejected>()),
      );
      expect(
        () => parseUserUrl('javascript:alert(1)'),
        throwsA(isA<UrlRejected>()),
      );
      expect(
        () => parseUserUrl('file:///etc/passwd'),
        throwsA(isA<UrlRejected>()),
      );
      expect(() => parseUserUrl(''), throwsA(isA<UrlRejected>()));
    },
  );

  test(
    'CORE-005 history keeps the last 50, newest first, without credentials',
    () async {
      final db = LibraryDatabase.memory();
      addTearDown(db.close);
      var t = DateTime.utc(2026);
      final h = UrlHistoryRepository(
        db,
        clock: () => t = t.add(const Duration(seconds: 1)),
      );
      for (var i = 0; i < 55; i++) {
        await h.record(parseUserUrl('https://h/$i.m3u8'));
      }
      await h.record(
        parseUserUrl('https://user:secret@h/3.m3u8', headers: {'Referer': 'r'}),
      );
      final rows = await h.recent();
      expect(rows, hasLength(50));
      expect(rows.first.url, 'https://h/3.m3u8');
      expect(rows.any((r) => r.url.contains('secret')), isFalse);
      expect(UrlHistoryRepository.toOpenable(rows.first).headers, {
        'Referer': 'r',
      });
      expect(rows.map((r) => r.url), isNot(contains('https://h/4.m3u8')));
    },
  );
}
