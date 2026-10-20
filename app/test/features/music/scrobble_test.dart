import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/scrobble/scrobble_services.dart';
import 'package:mediahro/features/music/scrobble/scrobbler.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

import '../../helpers.dart';
import 'music_screens_test.dart' show finish, settle;
import 'music_test_support.dart';

void main() {
  group('MUS-009 wire formats', () {
    test('MUS-009 ListenBrainz: token check, single and import listens, '
        'playing_now without a time', () async {
      final http = _Http()
        ..reply('/1/validate-token', 200, {'valid': true, 'user_name': 'amy'});
      final secure = _Secure();
      final lb = ListenBrainzService(http, secure);
      expect(await lb.signIn(' tok '), 'amy');
      expect(secure.values[ListenBrainzService.tokenKey], 'tok');
      http.reply('/1/submit-listens', 200, {'status': 'ok'});
      final t = ScrobbleTrack(
        artist: 'A',
        title: 'T',
        album: 'Al',
        duration: const Duration(seconds: 200),
        trackNumber: 3,
        playedAt: DateTime.utc(2026, 10, 20, 12),
      );
      await lb.submit([t]);
      final body =
          jsonDecode(utf8.decode(http.bodies.last)) as Map<String, Object?>;
      expect(body['listen_type'], 'single');
      final listen =
          (body['payload']! as List<Object?>).single! as Map<String, Object?>;
      expect(
        listen['listened_at'],
        DateTime.utc(2026, 10, 20, 12).millisecondsSinceEpoch ~/ 1000,
      );
      final meta = listen['track_metadata']! as Map<String, Object?>;
      expect(meta['artist_name'], 'A');
      expect(meta['release_name'], 'Al');
      expect(http.headers.last['authorization'], 'Token tok');
      await lb.submit([t, t]);
      expect(
        (jsonDecode(utf8.decode(http.bodies.last)) as Map)['listen_type'],
        'import',
      );
      await lb.nowPlaying(t);
      final np =
          jsonDecode(utf8.decode(http.bodies.last)) as Map<String, Object?>;
      expect(np['listen_type'], 'playing_now');
      expect(
        ((np['payload']! as List).single as Map).containsKey('listened_at'),
        isFalse,
      );
      http.reply('/1/submit-listens', 401, {});
      await expectLater(
        lb.submit([t]),
        throwsA(isA<ScrobbleError>().having((e) => e.auth, 'auth', isTrue)),
      );
    });

    test('MUS-009 Audioscrobbler: signed calls, mobile session, batch '
        'indexing, error codes', () async {
      final http = _Http();
      final secure = _Secure();
      final svc = AudioscrobblerService(
        id: 'lastfm',
        http: http,
        secure: secure,
        apiBase: Uri.https('ws.audioscrobbler.com', '/2.0/'),
        apiKey: 'KEY',
        apiSecret: 'SECRET',
      );
      http.reply('/2.0/', 200, {
        'session': {'name': 'amy', 'key': 'SK'},
      });
      expect(await svc.signIn('amy', 'pw'), 'amy');
      expect(secure.values['music.scrobble.lastfm.session'], 'SK');
      // The password is in the signed request, never stored.
      expect(secure.values.values, isNot(contains('pw')));
      final form = Uri.splitQueryString(utf8.decode(http.bodies.last));
      final expected = md5
          .convert(
            utf8.encode(
              'api_keyKEYmethodauth.getMobileSessionpasswordpwusernameamySECRET',
            ),
          )
          .toString();
      expect(form['api_sig'], expected);
      expect(form['format'], 'json');

      http.reply('/2.0/', 200, {'scrobbles': <String, Object?>{}});
      await svc.submit([
        ScrobbleTrack(artist: 'A', title: 'One', playedAt: DateTime.utc(2026)),
        ScrobbleTrack(
          artist: 'B',
          title: 'Two',
          album: 'X',
          playedAt: DateTime.utc(2026, 1, 1, 0, 5),
        ),
      ]);
      final s = Uri.splitQueryString(utf8.decode(http.bodies.last));
      expect(s['method'], 'track.scrobble');
      expect(s['sk'], 'SK');
      expect(s['artist[0]'], 'A');
      expect(s['track[1]'], 'Two');
      expect(s['album[1]'], 'X');
      expect(
        s['timestamp[1]'],
        '${DateTime.utc(2026, 1, 1, 0, 5).millisecondsSinceEpoch ~/ 1000}',
      );

      http.reply('/2.0/', 403, {'error': 9, 'message': 'Invalid session key'});
      await expectLater(
        svc.submit([
          ScrobbleTrack(artist: 'A', title: 'x', playedAt: DateTime.utc(2026)),
        ]),
        throwsA(isA<ScrobbleError>().having((e) => e.auth, 'auth', isTrue)),
      );
      http.reply('/2.0/', 503, {'error': 16, 'message': 'try later'});
      await expectLater(
        svc.submit([
          ScrobbleTrack(artist: 'A', title: 'x', playedAt: DateTime.utc(2026)),
        ]),
        throwsA(isA<ScrobbleError>().having((e) => e.auth, 'auth', isFalse)),
      );
    });

    test(
      'MUS-009 Last.fm needs keys from the build; Libre.fm works without',
      () {
        expect(AudioscrobblerService.lastFm(_Http(), _Secure()), isNull);
        expect(AudioscrobblerService.libreFm(_Http(), _Secure()).id, 'librefm');
      },
    );
  });

  group('MUS-009 scrobbler', () {
    late LibraryDatabase db;
    late ScriptedMusicEngine engine;
    late MusicPlayer player;
    late _FakeService svc;
    late Scrobbler scrobbler;
    late List<MusicTrack> songs;

    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 5));

    setUp(() async {
      db = LibraryDatabase.memory();
      final seed = MusicSeed(db);
      await seed.song(
        'a/1.flac',
        title: 'Long',
        artist: 'A',
        album: 'X',
        albumArtist: 'A',
        track: 1,
        durationMs: 600000,
      );
      await seed.song(
        'a/2.flac',
        title: 'Mid',
        artist: 'A',
        album: 'X',
        albumArtist: 'A',
        track: 2,
        durationMs: 100000,
      );
      await seed.song(
        'a/3.flac',
        title: 'Tiny',
        artist: 'A',
        album: 'X',
        albumArtist: 'A',
        track: 3,
        durationMs: 20000,
      );
      final lib = MusicLibrary(db);
      songs = await lib.albumTracks((await lib.albums()).single.groupKey);
      engine = ScriptedMusicEngine();
      player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: lib,
        files: localMusicFiles(db),
        openTimeout: const Duration(milliseconds: 100),
      );
      await player.init();
      svc = _FakeService();
      scrobbler = Scrobbler(
        db: db,
        prefs: MusicPrefs(db),
        player: player,
        services: [svc],
      );
      await scrobbler.setEnabled('fake', enabled: true);
      scrobbler.start();
    });
    tearDown(() async {
      await scrobbler.dispose();
      await player.dispose();
      await db.close();
    });

    Future<void> play(Duration to) async {
      // Real playback advances in small steps.
      var p = engine.current.position;
      while (p < to) {
        p += const Duration(seconds: 2);
        engine.at(p);
        await tick();
      }
    }

    test('MUS-009 a song counts after 4 minutes or half its length; seeks '
        'do not count; songs under 30 s never count', () async {
      await player.playTracks(songs);
      await tick();
      expect(svc.playingNow.single.title, 'Long');
      await play(const Duration(minutes: 3));
      expect(svc.submitted, isEmpty);
      // A seek forward is not listening.
      engine.at(const Duration(minutes: 9));
      await tick();
      expect(svc.submitted, isEmpty);
      engine.at(const Duration(minutes: 9, seconds: 2));
      await play(const Duration(minutes: 10));
      expect(svc.submitted.single.title, 'Long');

      await player.next(); // Mid: 100 s, needs 50 s
      await play(const Duration(seconds: 40));
      await player.next(); // skipped early: not counted
      await tick();
      expect(svc.submitted.map((t) => t.title), ['Long']);
      await play(const Duration(seconds: 20)); // Tiny: never
      engine.finishTrack();
      await tick();
      expect(svc.submitted.map((t) => t.title), ['Long']);
    });

    test('MUS-009 offline: listens wait in the queue and go out later in '
        'order; an auth error switches the service off', () async {
      svc.fail = const NetworkBlocked('x', 'off');
      await player.playTracks(songs);
      await play(const Duration(minutes: 5));
      await player.jumpTo(1);
      await play(const Duration(minutes: 1));
      await player.jumpTo(0);
      await tick();
      expect(await scrobbler.pending(), {'fake': 2});
      svc.fail = null;
      await scrobbler.flush();
      expect(svc.submitted.map((t) => t.title), ['Long', 'Mid']);
      expect(await scrobbler.pending(), isEmpty);
      svc.fail = const ScrobbleError('bad session', auth: true);
      await play(const Duration(minutes: 5));
      await tick();
      expect(await scrobbler.enabledServices(), isEmpty);
      expect(await scrobbler.pending(), {'fake': 1});
    });

    test(
      'MUS-009 excluded sources and disabled services are not scrobbled',
      () async {
        await scrobbler.setSourceExcluded(songs.first.sourceId, excluded: true);
        await player.playTracks(songs);
        await play(const Duration(minutes: 5));
        await tick();
        expect(svc.submitted, isEmpty);
        expect(await scrobbler.pending(), isEmpty);
        await scrobbler.setSourceExcluded(
          songs.first.sourceId,
          excluded: false,
        );
        await scrobbler.setEnabled('fake', enabled: false);
        await player.jumpTo(1);
        await play(const Duration(minutes: 1));
        await tick();
        expect(await scrobbler.pending(), isEmpty);
      },
    );
  });

  testWidgets('MUS-009 settings: consent, connect with a token, exclude a '
      'source, disconnect', (tester) async {
    final db = LibraryDatabase.memory();
    final dir = Directory.systemTemp.createTempSync('c2_scrobble');
    addTearDown(() async {
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort on Windows.
      }
    });
    await tester.runAsync(() async {
      await MusicSeed(db).song('a/1.flac', title: 'One', artist: 'A');
    });
    final http = _Http()
      ..reply('/1/validate-token', 200, {'valid': true, 'user_name': 'amy'});
    final secure = _Secure();
    tester.view
      ..physicalSize = const Size(420, 900) * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await tester.runAsync(memoryStore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store!),
          ...musicOverrides,
          libraryDatabaseProvider.overrideWithValue(db),
          appDataDirectoryProvider.overrideWithValue(dir),
          sourceResolverProvider.overrideWithValue(
            localMusicFiles(db).resolver,
          ),
          playbackEngineFactoryProvider.overrideWithValue(
            (_) => ScriptedMusicEngine(),
          ),
          scrobbleServicesProvider.overrideWithValue([
            ListenBrainzService(http, secure),
            AudioscrobblerService.libreFm(http, secure),
          ]),
        ],
        child: MediahroApp(router: buildRouter(initialLocation: '/music')),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Scrobbling'));
    await settle(tester);
    expect(find.text('ListenBrainz'), findsOneWidget);
    expect(find.text('Libre.fm'), findsOneWidget);
    expect(find.text('Not connected'), findsNWidgets(2));

    // Declining the consent changes nothing.
    final endpoint = CoreSettings.endpoint('listenbrainz');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect').first);
    await settle(tester);
    expect(find.textContaining('api.listenbrainz.org'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(store.get(endpoint), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
    await settle(tester);
    expect(store.get(endpoint), isTrue);
    await tester.enterText(find.byType(TextField), 'tok');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
    await settle(tester);
    expect(secure.values[ListenBrainzService.tokenKey], 'tok');
    expect(find.text('Connected as amy'), findsWidgets);
    expect(find.text('Send listens'), findsOneWidget);
    expect(find.text('Nothing waiting to be sent'), findsOneWidget);

    // Sources can be left out.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Music'));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).last),
    );
    expect(
      await tester.runAsync(
        () => container.read(scrobblerProvider).excludedSources(),
      ),
      isNotEmpty,
    );

    await tester.tap(find.text('Disconnect'));
    await settle(tester);
    expect(secure.values, isEmpty);
    expect(store.get(endpoint), isFalse);
    expect(find.text('Not connected'), findsNWidgets(2));
    await finish(tester);
  });
}

final class _FakeService implements ScrobbleService {
  final submitted = <ScrobbleTrack>[];
  final playingNow = <ScrobbleTrack>[];
  Exception? fail;

  @override
  String get id => 'fake';

  @override
  int get batchSize => 10;

  @override
  Future<bool> connected() async => true;

  @override
  Future<void> nowPlaying(ScrobbleTrack t) async => playingNow.add(t);

  @override
  Future<void> signOut() async {}

  @override
  Future<void> submit(List<ScrobbleTrack> listens) async {
    final f = fail;
    if (f != null) throw f;
    submitted.addAll(listens);
  }
}

final class _Http implements HttpTransport {
  final _replies = <String, (int, Object?)>{};
  final bodies = <List<int>>[];
  final headers = <Map<String, String>>[];

  void reply(String path, int status, Object? json) =>
      _replies[path] = (status, json);

  @override
  Future<HttpResponseData> send(HttpRequestData request) async {
    bodies.add(request.body ?? const []);
    headers.add(request.headers);
    final r = _replies[request.uri.path] ?? (404, null);
    return HttpResponseData(
      statusCode: r.$1,
      body: utf8.encode(jsonEncode(r.$2)),
    );
  }
}

final class _Secure implements SecureStorageFacade {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Object? noSuchMethod(Invocation invocation) => Future<void>.value();
}
