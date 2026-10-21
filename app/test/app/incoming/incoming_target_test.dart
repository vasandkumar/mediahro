import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/incoming/incoming_intent.dart';
import 'package:mediahro/app/incoming/incoming_target.dart';
import 'package:mediahro/platform/system_integration.dart';

IncomingRefusal? refusal(IncomingTarget t) =>
    t is IncomingRefused ? t.reason : null;

void main() {
  group('CORE-003 what is taken from other apps', () {
    test('a content URI from the system is a document', () {
      final t = classifyIncoming(Uri.parse('content://media/external/video/7'));
      expect(t, isA<IncomingDocument>());
    });

    test('http, https and the registered stream schemes are streams', () {
      for (final u in [
        'https://example.com/live/index.m3u8',
        'http://nas.local/a.mkv',
        'rtsp://192.168.1.20:554/stream1',
        'rtmp://example.com/live/x',
        'srt://example.com:9000',
        'mms://example.com/a',
      ]) {
        final t = classifyIncoming(Uri.parse(u));
        expect(t, isA<IncomingStream>(), reason: u);
      }
    });

    test('SYS-004 other schemes are refused', () {
      for (final u in [
        'smb://server/share/a.mkv',
        'ftp://server/a.mkv',
        'sftp://server/a.mkv',
        'dav://server/a.mkv',
        'javascript:alert(1)',
        'intent://x#Intent;scheme=http;end',
        'data:text/plain;base64,AAAA',
        'market://details?id=x',
        'android-app://com.example',
        'udp://239.0.0.1:1234',
        'rtp://239.0.0.1:1234',
        'about:blank',
        'tel:123',
        '/just/a/path',
      ]) {
        expect(
          refusal(classifyIncoming(Uri.parse(u))),
          IncomingRefusal.scheme,
          reason: u,
        );
      }
    });

    test('a stream without a host is refused', () {
      expect(
        refusal(classifyIncoming(Uri.parse('https:///x'))),
        IncomingRefusal.scheme,
      );
    });

    test('the scheme is read in any case', () {
      expect(
        classifyIncoming(Uri.parse('HTTPS://example.com/a')),
        isA<IncomingStream>(),
      );
      expect(
        refusal(classifyIncoming(Uri.parse('SMB://server/a'))),
        IncomingRefusal.scheme,
      );
    });

    test('a file URI is refused unless a held folder contains it', () {
      final inside = Uri.parse('file:///storage/movies/a.mkv');
      expect(
        refusal(classifyIncoming(inside)),
        IncomingRefusal.notPermitted,
        reason: 'no grants',
      );
      final roots = [Uri.parse('file:///storage/movies')];
      expect(
        classifyIncoming(inside, fileRoots: roots),
        isA<IncomingDocument>(),
      );
      expect(
        refusal(
          classifyIncoming(
            Uri.parse('file:///storage/movies-other/a.mkv'),
            fileRoots: roots,
          ),
        ),
        IncomingRefusal.notPermitted,
        reason: 'a sibling folder with the same prefix',
      );
      expect(
        refusal(
          classifyIncoming(
            Uri.parse('file:///storage/movies/../secret/a.mkv'),
            fileRoots: roots,
          ),
        ),
        IncomingRefusal.notPermitted,
        reason: 'parent segments',
      );
      expect(
        refusal(
          classifyIncoming(
            Uri.parse('file:///data/data/com.mediahro.app/files/vault.bin'),
            fileRoots: roots,
          ),
        ),
        IncomingRefusal.notPermitted,
      );
    });

    test("a content URI of the app's own providers is refused", () {
      for (final u in [
        'content://com.mediahro.app.files/vault/x',
        'content://com.mediahro.app.enterprise.files/x',
        'content://COM.MEDIAHRO.APP.testdocs/x',
      ]) {
        expect(
          refusal(classifyIncoming(Uri.parse(u))),
          IncomingRefusal.notPermitted,
          reason: u,
        );
      }
    });
  });

  group('SYS-003 what an intent may do', () {
    IncomingAction action(AppIntentKind kind, [String? arg]) =>
        actionForIntent(AppIntent(kind, argument: arg));

    String? go(IncomingAction a) => a is IncomingGo ? a.location : null;

    test('open mode goes to the named mode', () {
      expect(go(action(AppIntentKind.openMode, 'video')), '/video');
      expect(go(action(AppIntentKind.openMode, ' Music ')), '/music');
      expect(go(action(AppIntentKind.openMode, 'photos')), '/photos');
      expect(go(action(AppIntentKind.openMode, 'search')), '/search');
    });

    test('an unknown mode does nothing', () {
      expect(
        action(AppIntentKind.openMode, 'settings/privacy'),
        isA<IncomingIgnore>(),
      );
      expect(action(AppIntentKind.openMode), isA<IncomingIgnore>());
      expect(action(AppIntentKind.openMode, '../x'), isA<IncomingIgnore>());
    });

    test('the vault, hidden albums and private mode go to Photos, locked', () {
      for (final arg in [
        'vault',
        'Vault',
        'photos/vault',
        'hidden albums',
        'private',
        'private mode',
        'secret',
        'the decoy vault',
        'incognito',
      ]) {
        expect(go(action(AppIntentKind.openMode, arg)), '/photos', reason: arg);
      }
      // A playlist that names the vault is not looked up either.
      expect(go(action(AppIntentKind.playPlaylist, 'vault mix')), '/music');
      expect(namesSensitiveArea('vault'), isTrue);
      expect(namesSensitiveArea('holiday'), isFalse);
      expect(namesSensitiveArea(null), isFalse);
    });

    test('a shortcut never produces a route outside the shell', () {
      for (final kind in AppIntentKind.values) {
        for (final arg in [null, '', 'x', '/play', '/settings', 'vault']) {
          final a = action(kind, arg);
          if (a is IncomingGo) {
            expect(
              a.location,
              matches(RegExp(r'^/(video|music|photos|search)(\?.*)?$')),
              reason: '$kind $arg',
            );
          }
        }
      }
    });

    test('resume last returns to the last mode', () {
      expect(action(AppIntentKind.resumeLast), isA<IncomingResume>());
    });

    test('search carries the text as a query, never a path', () {
      expect(go(action(AppIntentKind.search, 'cats')), '/search?q=cats');
      expect(go(action(AppIntentKind.search, 'a b&c')), '/search?q=a+b%26c');
      expect(go(action(AppIntentKind.search, '  ')), '/search');
      expect(go(action(AppIntentKind.search)), '/search');
      expect(
        go(action(AppIntentKind.search, '../settings')),
        '/search?q=..%2Fsettings',
      );
    });

    test('search text is cut and stripped of control characters', () {
      final long = go(action(AppIntentKind.search, 'x' * 500))!;
      expect(
        Uri.parse(long).queryParameters['q'],
        hasLength(incomingQueryLimit),
      );
      expect(
        Uri.parse(go(action(AppIntentKind.search, 'a\nb\u0000c'))!)
            .queryParameters['q'],
        'a b c',
      );
    });
  });
}
