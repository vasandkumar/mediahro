import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/fingerprint/acoustid_client.dart';
import 'package:mediahro/features/music/fingerprint/fingerprint_service.dart';
import 'package:mediahro/features/music/fingerprint/track_identifier.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_editor.dart';
import 'package:mediahro/features/music/ui/identify_sheet.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

import '../../helpers.dart';
import 'music_test_support.dart';
import 'tag_fixtures.dart';

/// MUS-010: the on-device fingerprint, the opt-in AcoustID lookup and the
/// safe tag write that follows a pick.
void main() {
  const lookupResponse = {
    'status': 'ok',
    'results': [
      {
        'id': 'low',
        'score': 0.61,
        'recordings': [
          {
            'id': 'rec-b',
            'title': 'Other Song',
            'artists': [
              {'name': 'Cy'},
            ],
          },
        ],
      },
      {
        'id': 'hit',
        'score': 0.97,
        'recordings': [
          {
            'id': 'rec-a',
            'title': 'Hey Jude',
            'artists': [
              {'name': 'The Beatles', 'joinphrase': ' & '},
              {'name': 'Friends'},
            ],
            'releasegroups': [
              {
                'title': 'Past Masters',
                'type': 'Album',
                'secondarytypes': ['Compilation'],
                'releases': [
                  {
                    'date': {'year': 1988},
                  },
                ],
              },
              {
                'title': 'Hey Jude',
                'type': 'Album',
                'releases': [
                  {
                    'date': {'year': 1970, 'month': 2},
                  },
                  {
                    'date': {'year': 1969},
                  },
                  {'title': 'no date'},
                ],
              },
            ],
          },
          // The same song again on a single: still one entry per
          // title, artist and album.
          {
            'id': 'rec-a2',
            'title': 'Hey Jude',
            'artists': [
              {'name': 'The Beatles', 'joinphrase': ' & '},
              {'name': 'Friends'},
            ],
            'releasegroups': [
              {
                'title': 'Hey Jude',
                'type': 'Album',
                'releases': [
                  {
                    'date': {'year': 1969},
                  },
                ],
              },
            ],
          },
          {'id': 'untitled', 'title': ' '},
        ],
      },
    ],
  };

  group('MUS-010 AcoustID', () {
    test('MUS-010 matches come best first, deduplicated, with the plain '
        'album and its earliest year', () {
      final m = AcoustIdClient.parseMatches(lookupResponse);
      expect(m.map((e) => e.recordingId), ['rec-a', 'rec-b']);
      expect(m.first.title, 'Hey Jude');
      expect(m.first.artist, 'The Beatles & Friends');
      expect(m.first.album, 'Hey Jude');
      expect(m.first.year, 1969);
      expect(m.first.score, 0.97);
      expect(m.last.album, isNull);
      expect(AcoustIdClient.parseMatches({'status': 'ok'}), isEmpty);
    });

    test('MUS-010 the lookup posts the fingerprint and the length, nothing '
        'else about the song', () async {
      final http = _Http([_json(lookupResponse)]);
      final client = AcoustIdClient(transport: http, apiKey: 'KEY');
      final res = await client.lookup(const AudioFingerprint('AQAD+x y', 215));
      expect(res, hasLength(2));
      final r = http.requests.single;
      expect(r.method, 'POST');
      expect(r.uri.host, 'api.acoustid.org');
      expect(r.uri.path, '/v2/lookup');
      final form = Uri.splitQueryString(utf8.decode(r.body!));
      expect(form.keys.toSet(), {
        'client',
        'format',
        'meta',
        'duration',
        'fingerprint',
      });
      expect(form['client'], 'KEY');
      expect(form['duration'], '215');
      expect(form['fingerprint'], 'AQAD+x y');
      expect(form['meta'], 'recordings releasegroups releases');
    });

    test('MUS-010 errors map to reasons; a build without a key does not '
        'look up', () async {
      Future<AcoustIdFailure?> fail(HttpResponseData r) async {
        try {
          await AcoustIdClient(
            transport: _Http([r]),
            apiKey: 'K',
          ).lookup(const AudioFingerprint('x', 1));
        } on AcoustIdException catch (e) {
          return e.reason;
        }
        return null;
      }

      expect(await fail(_json({}, status: 429)), AcoustIdFailure.rateLimited);
      expect(
        await fail(
          _json({
            'status': 'error',
            'error': {'code': 4, 'message': 'invalid API key'},
          }),
        ),
        AcoustIdFailure.invalidKey,
      );
      expect(
        await fail(
          _json({
            'status': 'error',
            'error': {'code': 3, 'message': 'invalid fingerprint'},
          }),
        ),
        AcoustIdFailure.invalidFingerprint,
      );
      expect(
        await fail(const HttpResponseData(statusCode: 502, body: [60])),
        AcoustIdFailure.server,
      );
      final none = AcoustIdClient(transport: _Http([]));
      expect(none.available, isFalse);
      await expectLater(
        none.lookup(const AudioFingerprint('x', 1)),
        throwsA(isA<AcoustIdException>()),
      );
    });

    test(
      "MUS-010 requests are spaced under AcoustID's three per second",
      () async {
        var now = DateTime.utc(2026);
        final waits = <Duration>[];
        final client = AcoustIdClient(
          transport: _Http([_json(lookupResponse), _json(lookupResponse)]),
          apiKey: 'K',
          clock: () => now,
          delay: (d) async {
            waits.add(d);
            now = now.add(d);
          },
        );
        await client.lookup(const AudioFingerprint('x', 1));
        now = now.add(const Duration(milliseconds: 100));
        await client.lookup(const AudioFingerprint('x', 1));
        expect(waits, [const Duration(milliseconds: 250)]);
      },
    );

    test('MUS-010 the lookup is refused while the endpoint is off', () async {
      final client = AcoustIdClient(
        transport: _Http([], blocked: true),
        apiKey: 'K',
      );
      await expectLater(
        client.lookup(const AudioFingerprint('x', 1)),
        throwsA(isA<NetworkBlocked>()),
      );
    });
  });

  group('MUS-010 fingerprint', () {
    late LibraryDatabase db;
    late ScriptedMusicEngine engine;
    late MusicTrack track;
    final calls = <(int, int)>[];

    setUp(() async {
      db = LibraryDatabase.memory();
      engine = ScriptedMusicEngine();
      calls.clear();
      await MusicSeed(db).song(
        'a/1.flac',
        title: 'One',
        artist: 'A',
        album: 'X',
        albumArtist: 'A',
        durationMs: 215000,
      );
      track = (await MusicLibrary(db).songs()).single;
    });
    tearDown(() => db.close());

    TrackFingerprinter fingerprinter() => TrackFingerprinter(
      engine: engine,
      files: localMusicFiles(db),
      compute: (pcm, rate) async {
        calls.add((pcm.length, rate));
        return 'FP${pcm.first}';
      },
    );

    Float32List ramp(int n, double v) => Float32List(n)..fillRange(0, n, v);

    test('MUS-010 decodes at the fingerprint rate, converts to 16 bit, and '
        'stops reading after two minutes', () async {
      const second = fingerprintRate;
      engine.decoded = [
        for (var i = 0; i < 6; i++) ramp(second * 30, i == 0 ? 0.5 : 2),
      ];
      final fp = await fingerprinter().of(track);
      // 4 chunks of 30 s are 120 s: the rest is never read.
      expect(engine.decodedRead, 4);
      expect(engine.decodeEnd, const Duration(seconds: fingerprintSeconds));
      expect(calls.single, (second * fingerprintSeconds, fingerprintRate));
      // 0.5 → 16383/16384, values past full scale clamp.
      expect(fp.encoded, 'FP16384');
      expect(fp.durationSeconds, 215);
    });

    test('MUS-010 a short song uses what was decoded for its length, and '
        'nothing to decode or under three seconds is refused', () async {
      engine.decoded = [ramp(fingerprintRate * 10, 0.1)];
      final fp =
          await TrackFingerprinter(
            engine: engine,
            files: localMusicFiles(db),
            compute: (_, _) async => 'x',
          ).of(
            const MusicTrack(
              itemId: 1,
              sourceId: 1,
              relPath: 'a/1.flac',
              parentPath: 'a',
              title: 'One',
            ),
          );
      expect(fp.durationSeconds, 10);

      engine.decoded = const [];
      await expectLater(
        fingerprinter().of(track),
        throwsA(
          isA<FingerprintException>().having(
            (e) => e.reason,
            'reason',
            FingerprintFailure.noAudio,
          ),
        ),
      );
      engine.decoded = [ramp(fingerprintRate * 2, 0.1)];
      await expectLater(
        fingerprinter().of(track),
        throwsA(
          isA<FingerprintException>().having(
            (e) => e.reason,
            'reason',
            FingerprintFailure.tooShort,
          ),
        ),
      );
    });
  });

  group('MUS-010 identify and apply', () {
    late Directory dir;
    late LibraryDatabase db;
    late TrackIdentifier identifier;
    late _Http http;
    late MusicTrack track;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('c2_identify');
      db = LibraryDatabase.memory();
      final seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      File('${dir.path}/a.flac').writeAsBytesSync(flac(['TITLE=Track 01']));
      await seed.song('a.flac', title: 'Track 01', durationMs: 215000);
      track = (await MusicLibrary(db).songs()).single;
      final engine = ScriptedMusicEngine()
        ..decoded = [Float32List(fingerprintRate * 20)];
      http = _Http([_json(lookupResponse)]);
      identifier = TrackIdentifier(
        fingerprinter: TrackFingerprinter(
          engine: engine,
          files: localMusicFiles(db),
          compute: (_, _) async => 'FP',
        ),
        client: AcoustIdClient(transport: http, apiKey: 'K'),
        editor: TagEditor(
          db: db,
          files: localMusicFiles(db),
          art: ArtworkStore(db, Directory('${dir.path}/art')),
          prefs: MusicPrefs(db),
          cacheDir: Directory('${dir.path}/cache'),
        ),
      );
    });
    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may hold a handle briefly.
      }
    });

    test(
      'MUS-010 identify returns matches and nothing is written until '
      'one is picked; applying writes title, artist, album and year',
      () async {
        var looked = false;
        final found = await identifier.identify(
          track,
          onFingerprinted: () => looked = http.requests.isEmpty,
        );
        expect(
          looked,
          isTrue,
          reason: 'the lookup starts after the fingerprint',
        );
        expect(found.first.title, 'Hey Jude');
        expect(
          (await TagReader.readFile('${dir.path}/a.flac')).title,
          'Track 01',
        );

        final res = await identifier.apply(track, found.first);
        expect(res.changed, 1);
        final t = await TagReader.readFile('${dir.path}/a.flac');
        expect(t.title, 'Hey Jude');
        expect(t.values(TagField.artist), ['The Beatles & Friends']);
        expect(t.album, 'Hey Jude');
        expect(t.values(TagField.date), ['1969']);
        final row = (await MusicLibrary(db).songs()).single;
        expect(row.title, 'Hey Jude');
        expect(row.album, 'Hey Jude');
      },
    );
  });

  group('MUS-010 identify sheet', () {
    late Directory dir;
    late LibraryDatabase db;
    late _Http http;
    late MusicTrack track;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('c2_identify_ui');
      db = LibraryDatabase.memory();
      final seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      File('${dir.path}/a.flac').writeAsBytesSync(flac(['TITLE=Track 01']));
      await seed.song('a.flac', title: 'Track 01', durationMs: 215000);
      track = (await MusicLibrary(db).songs()).single;
      http = _Http([_json(lookupResponse)]);
    });
    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may hold a handle briefly.
      }
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<SettingsStore> open(
      WidgetTester tester, {
      String apiKey = 'K',
      bool endpointOn = false,
    }) async {
      final store = (await tester.runAsync(memoryStore))!;
      if (endpointOn) {
        store.set(CoreSettings.endpoint(Endpoints.acoustId.id), true);
      }
      final identifier = TrackIdentifier(
        fingerprinter: TrackFingerprinter(
          engine: ScriptedMusicEngine()
            ..decoded = [Float32List(fingerprintRate * 20)],
          files: localMusicFiles(db),
          compute: (_, _) async => 'FP',
        ),
        client: AcoustIdClient(transport: http, apiKey: apiKey),
        editor: TagEditor(
          db: db,
          files: localMusicFiles(db),
          art: ArtworkStore(db, Directory('${dir.path}/art')),
          prefs: MusicPrefs(db),
          cacheDir: Directory('${dir.path}/cache'),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(store),
            trackIdentifierProvider.overrideWithValue(identifier),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(showIdentifySheet(context, track)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      return store;
    }

    testWidgets('MUS-010 off by default: the sheet asks first and nothing '
        'is sent until the user allows it; then the match is applied', (
      tester,
    ) async {
      final store = await open(tester);
      expect(find.textContaining('acoustid.org'), findsOneWidget);
      expect(http.requests, isEmpty);
      expect(store.get(CoreSettings.endpoint(Endpoints.acoustId.id)), isFalse);

      await tester.tap(find.text('Allow and identify'));
      await settle(tester);
      expect(store.get(CoreSettings.endpoint(Endpoints.acoustId.id)), isTrue);
      expect(find.text('Hey Jude'), findsOneWidget);
      expect(find.text('97% match'), findsOneWidget);
      expect(find.text('Hey Jude (1969)'), findsOneWidget);
      expect(
        (await tester.runAsync(() => TagReader.readFile('${dir.path}/a.flac')))!
            .title,
        'Track 01',
      );

      await tester.tap(find.text('Hey Jude').first);
      // The write is real file I/O: give it real time.
      for (var i = 0; i < 100; i++) {
        if (find.text('Tags updated').evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Tags updated'), findsOneWidget);
      expect(
        (await tester.runAsync(() => TagReader.readFile('${dir.path}/a.flac')))!
            .title,
        'Hey Jude',
      );
    });

    testWidgets('MUS-010 with the endpoint already on it starts at once', (
      tester,
    ) async {
      await open(tester, endpointOn: true);
      expect(find.text('Hey Jude'), findsOneWidget);
      expect(http.requests, hasLength(1));
    });

    testWidgets('MUS-010 without an AcoustID key nothing is offered or sent', (
      tester,
    ) async {
      await open(tester, apiKey: '', endpointOn: true);
      expect(find.textContaining("isn't available"), findsOneWidget);
      expect(http.requests, isEmpty);
    });

    testWidgets('MUS-010 a song AcoustID does not know says so', (
      tester,
    ) async {
      http = _Http([
        _json({'status': 'ok', 'results': <Object?>[]}),
      ]);
      await open(tester, endpointOn: true);
      expect(find.text('No match found for this song.'), findsOneWidget);
    });
  });
}

HttpResponseData _json(Map<String, Object?> body, {int status = 200}) =>
    HttpResponseData(statusCode: status, body: utf8.encode(jsonEncode(body)));

final class _Http implements HttpTransport {
  _Http(this._responses, {this.blocked = false});

  final List<HttpResponseData> _responses;
  final bool blocked;
  final requests = <HttpRequestData>[];

  @override
  Future<HttpResponseData> send(HttpRequestData request) async {
    if (blocked) {
      throw const NetworkBlocked('api.acoustid.org', 'endpoint is turned off');
    }
    requests.add(request);
    return _responses.removeAt(0);
  }
}
