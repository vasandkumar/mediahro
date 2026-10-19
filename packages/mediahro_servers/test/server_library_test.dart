import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:test/test.dart';

void main() {
  test('every 1.0 server family is represented (NET-010…017, POD-003)', () {
    expect(
      ServerKind.values.map((k) => k.name),
      containsAll(<String>[
        'jellyfin',
        'emby',
        'plex',
        'subsonic',
        'immich',
        'nextcloud',
        'audiobookshelf',
        'mediahro',
      ]),
    );
  });

  test('PRIV-006 accounts hold only a secret reference', () {
    final a = ServerAccount(
      id: 'x',
      kind: ServerKind.jellyfin,
      baseUri: Uri.parse('https://jf.example.test'),
      displayName: 'Home',
      secretRef: 'keychain:x',
    );
    expect(a.secretRef, startsWith('keychain:'));
  });
}
