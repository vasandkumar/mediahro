import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/sources/cloud/cloud_file_system.dart';
import 'package:mediahro/core/sources/cloud/cloud_providers.dart';
import 'package:mediahro/core/sources/cloud/oauth.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/platform/platform_facades.dart';

final class _Lan implements NetworkPolicy {
  @override
  bool isEnabled(NetworkEndpoint endpoint) => false;

  @override
  bool isUserConfiguredHost(String host) => host == '127.0.0.1';

  @override
  void recordUse(NetworkEndpoint endpoint, DateTime at) {}
}

/// Canned provider responses by path; records every call.
final class _FakeCalls implements CloudCalls {
  _FakeCalls(this.routes);

  final Map<String, List<Map<String, Object?>>> routes;
  final calls = <(String, Uri, Object?)>[];

  @override
  Future<String> token() async => 'tok';

  @override
  Future<Map<String, Object?>> json(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
    bool form = false,
  }) async {
    calls.add((method, uri, body));
    final list = routes[uri.path]!;
    return list.length > 1 ? list.removeAt(0) : list.first;
  }
}

final class _Browser implements AuthBrowserFacade {
  _Browser(this.reply);

  final Uri Function(Uri auth) reply;
  Uri? asked;

  @override
  Future<Uri> authorize(Uri authorizationUrl, Uri redirectUri) async {
    asked = authorizationUrl;
    return reply(authorizationUrl);
  }
}

void main() {
  test('NET-007 PKCE S256 matches RFC 7636 appendix B', () {
    expect(
      pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  group('NET-007 OAuth', () {
    late HttpServer server;
    late NetworkGateway gw;
    final forms = <Map<String, String>>[];

    setUp(() async {
      forms.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((r) async {
          final form = Uri.splitQueryString(await utf8.decodeStream(r));
          forms.add(form);
          r.response.headers.contentType = ContentType.json;
          if (form['grant_type'] == 'authorization_code' &&
              form['code'] == 'c0de') {
            r.response.write(
              jsonEncode({
                'access_token': 'A1',
                'refresh_token': 'R1',
                'expires_in': 3600,
              }),
            );
          } else if (form['grant_type'] == 'refresh_token') {
            r.response.write(
              jsonEncode({'access_token': 'A2', 'expires_in': 60}),
            );
          } else {
            r.response
              ..statusCode = 400
              ..write(jsonEncode({'error': 'invalid_grant'}));
          }
          await r.response.close();
        });
      gw = NetworkGateway(_Lan());
    });
    tearDown(() async {
      gw.close();
      await server.close(force: true);
    });

    OAuthClient client() => OAuthClient(
      OAuthConfig(
        authorize: Uri.parse('https://accounts.example/auth'),
        token: Uri.parse('http://127.0.0.1:${server.port}/token'),
        scopes: const ['read', 'offline'],
        clientId: 'mediahro-test',
      ),
      HttpSession(gw),
      clock: () => DateTime.utc(2026, 10, 19),
    );

    test(
      'authorization code + PKCE, state check, refresh keeps the refresh token',
      () async {
        final c = client();
        final browser = _Browser(
          (auth) => Uri.parse(
            'mediahro://oauth?code=c0de&state=${auth.queryParameters['state']}',
          ),
        );
        final tokens = await c.signIn(browser, Uri.parse('mediahro://oauth'));
        final q = browser.asked!.queryParameters;
        expect(q['code_challenge_method'], 'S256');
        expect(q['client_id'], 'mediahro-test');
        expect(q['scope'], 'read offline');
        expect(
          pkceChallenge(forms.single['code_verifier']!),
          q['code_challenge'],
        );
        expect(
          forms.single['client_secret'],
          isNull,
          reason: 'public client, no secret in the app',
        );
        expect((tokens.accessToken, tokens.refreshToken), ('A1', 'R1'));
        final fresh = await c.refresh(tokens);
        expect((fresh.accessToken, fresh.refreshToken), ('A2', 'R1'));
        expect(OAuthTokens.decode(fresh.encode()).accessToken, 'A2');
      },
    );

    test('a forged state or a provider error is refused', () async {
      final c = client();
      await expectLater(
        c.signIn(
          _Browser((_) => Uri.parse('mediahro://oauth?code=c0de&state=evil')),
          Uri.parse('mediahro://oauth'),
        ),
        throwsA(
          isA<OAuthError>().having((e) => e.code, 'code', 'state_mismatch'),
        ),
      );
      await expectLater(
        c.signIn(
          _Browser((_) => Uri.parse('mediahro://oauth?error=access_denied')),
          Uri.parse('mediahro://oauth'),
        ),
        throwsA(
          isA<OAuthError>().having((e) => e.code, 'code', 'access_denied'),
        ),
      );
    });

    test('desktop loopback redirect receives the code', () async {
      final lb = await LoopbackRedirect.start();
      final got = lb.next(doneHtml: '<p>ok</p>');
      final http = HttpClient();
      final req = await http.getUrl(
        lb.redirectUri.replace(queryParameters: {'code': 'x', 'state': 's'}),
      );
      final res = await req.close();
      expect(await utf8.decodeStream(res), '<p>ok</p>');
      expect((await got).queryParameters['code'], 'x');
      http.close();
    });
  });

  test(
    'NET-007 Google Drive: paged listing skips Docs, downloads with the bearer',
    () async {
      final calls = _FakeCalls({
        '/drive/v3/files': [
          {
            'nextPageToken': 'p2',
            'files': [
              {
                'id': 'f1',
                'name': 'Films',
                'mimeType': 'application/vnd.google-apps.folder',
              },
              {
                'id': 'd1',
                'name': 'Notes',
                'mimeType': 'application/vnd.google-apps.document',
              },
            ],
          },
          {
            'files': [
              {
                'id': 'v1',
                'name': 'clip.mp4',
                'mimeType': 'video/mp4',
                'size': '1234',
                'modifiedTime': '2026-01-02T03:04:05Z',
              },
            ],
          },
        ],
      });
      const p = GoogleDriveProvider();
      final list = await p.list(
        calls,
        const CloudEntry(id: 'root', name: '', isFolder: true),
      );
      expect(list.map((e) => (e.name, e.isFolder, e.size)), [
        ('Films', true, null),
        ('clip.mp4', false, 1234),
      ]);
      expect(calls.calls[1].$2.queryParameters['pageToken'], 'p2');
      final (url, headers) = await p.download(calls, list.last);
      expect(url.queryParameters['alt'], 'media');
      expect(headers['Authorization'], 'Bearer tok');
    },
  );

  test('NET-007 OneDrive, Dropbox, Box, pCloud, Yandex listings and download links', () async {
    final od = _FakeCalls({
      '/v1.0/me/drive/items/root/children': [
        {
          'value': [
            {
              'id': 'a',
              'name': 'Music',
              'folder': {'childCount': 1},
            },
            {
              'id': 'b',
              'name': 'x.flac',
              'file': <String, Object?>{},
              'size': 10,
            },
          ],
          '@odata.nextLink': 'https://evil.example/next',
        },
      ],
      '/v1.0/me/drive/items/b': [
        {'@microsoft.graph.downloadUrl': 'https://public.1drv.com/x?sig'},
      ],
    });
    final odList = await const OneDriveProvider().list(
      od,
      const CloudEntry(id: 'root', name: '', isFolder: true),
    );
    expect(odList, hasLength(2), reason: 'paging stops at foreign hosts');
    final (odUrl, odHeaders) = await const OneDriveProvider().download(
      od,
      odList.last,
    );
    expect(odUrl.host, 'public.1drv.com');
    expect(odHeaders, isEmpty, reason: 'no bearer to the CDN');

    final dbx = _FakeCalls({
      '/2/files/list_folder': [
        {
          'entries': [
            {
              '.tag': 'folder',
              'id': 'id:1',
              'name': 'Photos',
              'path_lower': '/photos',
            },
          ],
          'has_more': true,
          'cursor': 'c1',
        },
      ],
      '/2/files/list_folder/continue': [
        {
          'entries': [
            {
              '.tag': 'file',
              'id': 'id:2',
              'name': 'a.jpg',
              'path_lower': '/a.jpg',
              'size': 5,
            },
            {'.tag': 'deleted', 'name': 'gone'},
          ],
          'has_more': false,
        },
      ],
      '/2/files/get_temporary_link': [
        {'link': 'https://abc.dl.dropboxusercontent.com/x'},
      ],
    });
    final dl = await const DropboxProvider().list(
      dbx,
      const CloudEntry(id: '', name: '', isFolder: true, path: ''),
    );
    expect(dl.map((e) => e.name), ['Photos', 'a.jpg']);
    expect(
      (await const DropboxProvider().download(dbx, dl.last)).$1.host,
      'abc.dl.dropboxusercontent.com',
    );

    final box = _FakeCalls({
      '/2.0/folders/0/items': [
        {
          'entries': [
            {'type': 'file', 'id': '9', 'name': 'b.mkv', 'size': 77},
          ],
          'total_count': 1,
        },
      ],
    });
    expect(
      (await const BoxProvider().list(
        box,
        const CloudEntry(id: '0', name: '', isFolder: true),
      )).single.size,
      77,
    );

    final pc = _FakeCalls({
      '/listfolder': [
        {
          'result': 0,
          'metadata': {
            'contents': [
              {
                'isfolder': false,
                'fileid': 42,
                'name': 'song.mp3',
                'size': 3,
                'modified': 'Thu, 02 Jan 2026 03:04:05 +0000',
              },
            ],
          },
        },
      ],
      '/getfilelink': [
        {
          'hosts': ['c123.pcloud.com'],
          'path': '/dl/song.mp3',
        },
      ],
    });
    final pl = await const PCloudProvider().list(
      pc,
      const CloudEntry(id: '0', name: '', isFolder: true),
    );
    expect(pl.single.modified, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(
      (await const PCloudProvider().download(pc, pl.single)).$1.toString(),
      'https://c123.pcloud.com/dl/song.mp3',
    );

    final ya = _FakeCalls({
      '/v1/disk/resources': [
        {
          '_embedded': {
            'items': [
              {
                'name': 'v.mp4',
                'path': 'disk:/v.mp4',
                'type': 'file',
                'size': 8,
              },
            ],
            'total': 1,
          },
        },
      ],
      '/v1/disk/resources/download': [
        {'href': 'https://downloader.disk.yandex.ru/x'},
      ],
    });
    final yl = await const YandexDiskProvider().list(
      ya,
      const CloudEntry(id: 'disk:/', name: '', isFolder: true, path: 'disk:/'),
    );
    expect(
      (await const YandexDiskProvider().download(ya, yl.single)).$1.host,
      'downloader.disk.yandex.ru',
    );
  });

  test(
    'NET-007 cloud file system resolves paths to ids and caches listings',
    () async {
      final calls = _FakeCalls({
        '/drive/v3/files': [
          {
            'files': [
              {
                'id': 'f1',
                'name': 'Films',
                'mimeType': 'application/vnd.google-apps.folder',
              },
            ],
          },
          {
            'files': [
              {
                'id': 'v1',
                'name': 'clip.mp4',
                'mimeType': 'video/mp4',
                'size': '12',
              },
            ],
          },
        ],
      });
      final gw = NetworkGateway(_Lan());
      addTearDown(gw.close);
      final fs = CloudFileSystem(
        provider: const GoogleDriveProvider(),
        api: calls,
        downloadSession: HttpSession(gw),
      );
      final root = Uri.parse('cloud://gdrive/me@example.com/');
      final top = await fs.list(root).toList();
      expect(top.single.uri.toString(), 'cloud://gdrive/me@example.com/Films/');
      final films = await fs.list(top.single.uri).toList();
      expect(films.single.size, 12);
      final before = calls.calls.length;
      await fs.stat(films.single.uri);
      expect(
        calls.calls.length,
        before,
        reason: 'served from the listing cache',
      );
    },
  );

  test(
    'PRIV-004 cloud provider hosts are allowed only for connected accounts',
    () async {
      final db = LibraryDatabase.memory();
      addTearDown(db.close);
      final p = await PersistentNetworkPolicy.load(db);
      expect(p.isUserConfiguredHost('www.googleapis.com'), isFalse);
      p.allowProviderForSession(const GoogleDriveProvider());
      expect(p.isUserConfiguredHost('www.googleapis.com'), isTrue);
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              kind: SourceKind.cloud,
              name: 'Dropbox',
              rootUri: 'cloud://dropbox/me/',
              options: const Value('{"provider":"dropbox"}'),
              addedAt: DateTime.utc(2026),
            ),
          );
      await p.refreshUserHosts();
      expect(p.isUserConfiguredHost('abc.dl.dropboxusercontent.com'), isTrue);
      expect(p.isUserConfiguredHost('dl.boxcloud.com'), isFalse);
      await p.dispose();
    },
  );
}
