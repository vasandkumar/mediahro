import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/abs/abs_account.dart';
import 'package:mediahro/features/music/abs/abs_player.dart';
import 'package:mediahro/features/music/abs/abs_service.dart';
import 'package:mediahro/features/music/abs/abs_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

import 'music_test_support.dart';
import 'podcast_test_support.dart';

/// POD-003 against a pretend Audiobookshelf server (the `ServerLibrary`
/// contract): browsing, offline copies, and playing with the server keeping
/// the place.
void main() {
  late LibraryDatabase db;
  late FakeServer server;
  late AbsAccount account;
  late AbsStore store;
  late FakeDownloads downloads;
  late FakeNet net;
  late AbsService service;
  late Directory art;

  setUp(() async {
    db = LibraryDatabase.memory();
    server = FakeServer();
    account = AbsAccount(
      ServerAccount(
        id: 'acc1',
        kind: ServerKind.audiobookshelf,
        baseUri: Uri.parse('https://abs.example'),
        displayName: 'Home server',
      ),
      server,
    );
    store = AbsStore(MusicPrefs(db));
    downloads = FakeDownloads();
    net = FakeNet()
      ..serve('https://abs.example/cover/dune', 'COVER', type: 'image/png');
    art = await Directory.systemTemp.createTemp('c2_abs_art');
    service = AbsService(
      store: store,
      downloads: downloads,
      http: net.http,
      artDir: art,
    );
  });
  tearDown(() async {
    await db.close();
    try {
      await art.delete(recursive: true);
    } on FileSystemException {
      // Windows may hold a handle briefly.
    }
  });

  group('POD-003 browsing', () {
    test(
      'POD-003 libraries, pages by cursor, search, and what to continue '
      'listening to; an unreachable server only loses its own items',
      () async {
        final libs = await service.libraries(account);
        expect(libs.map((l) => l.title), ['Audiobooks', 'Podcasts']);
        final first = await service.browse(account, 'lib1');
        expect(first.items.map((i) => i.title), ['Dune', 'Emma']);
        expect(first.nextCursor, 'c2');
        final second = await service.browse(account, 'lib1', cursor: 'c2');
        expect(second.items.map((i) => i.title), ['Persuasion']);
        expect(second.nextCursor, isNull);
        expect(
          (await service.search(account, 'dun')).items.single.title,
          'Dune',
        );

        final broken = AbsAccount(
          ServerAccount(
            id: 'acc2',
            kind: ServerKind.audiobookshelf,
            baseUri: Uri.parse('https://down.example'),
            displayName: 'Down',
          ),
          FakeServer()..unreachable = true,
        );
        final cont = await service.continueListening([broken, account]);
        expect(cont.map((e) => e.item.title), ['Dune']);
        expect(cont.single.account.name, 'Home server');
      },
    );

    test("POD-003 what an item says about itself comes from the client's "
        'extra fields', () {
      const book = ServerItem(
        id: 'b',
        kind: ServerItemKind.book,
        title: 'Dune',
        extra: {'author': ' Frank Herbert ', 'narrator': '', 'series': 'Dune'},
      );
      expect(book.author, 'Frank Herbert');
      expect(book.narrator, isNull);
      expect(book.series, 'Dune');
      expect(book.playable, isTrue);
      expect(book.isPodcast, isFalse);
      expect(
        const ServerItem(
          id: 'p',
          kind: ServerItemKind.podcast,
          title: 'P',
        ).isPodcast,
        isTrue,
      );
    });

    test('POD-003 covers are fetched once, through the gateway', () async {
      const item = ServerItem(
        id: 'dune',
        kind: ServerItemKind.book,
        title: 'Dune',
      );
      expect(await service.artPath(item), isNull);
      final withArt = ServerItem(
        id: 'dune',
        kind: ServerItemKind.book,
        title: 'Dune',
        artworkUri: Uri.parse('https://abs.example/cover/dune'),
      );
      final path = (await service.artPath(withArt))!;
      expect(File(path).readAsStringSync(), 'COVER');
      expect(path, endsWith('.png'));
      final hits = net.requests.length;
      expect(await service.artPath(withArt), path);
      expect(net.requests.length, hits, reason: 'the second one is cached');
      expect(
        await service.artPath(
          ServerItem(
            id: 'x',
            kind: ServerItemKind.book,
            title: 'X',
            artworkUri: Uri.parse('https://abs.example/missing.jpg'),
          ),
        ),
        isNull,
      );
    });
  });

  group('POD-003 offline copies', () {
    const dune = ServerItem(
      id: 'dune',
      kind: ServerItemKind.book,
      title: 'Dune',
    );

    test('POD-003 the address the server gives is kept; status and removal '
        'follow it', () async {
      await service.download(account, dune);
      expect(
        downloads.enqueued.single.$1.toString(),
        'https://abs.example/download/dune?token=t1',
      );
      expect(
        (await store.item('acc1', 'dune')).downloadUri,
        'https://abs.example/download/dune?token=t1',
      );
      // The server would give another address next time; the first is kept.
      server.token = 't2';
      expect(
        (await service.downloadStatus(account, dune))?.state,
        DownloadState.queued,
      );
      expect(await service.localFile(account, dune), isNull);
      final f = File('${art.path}/dune.m4b');
      downloads.files['https://abs.example/download/dune?token=t1'] = f;
      expect(await service.localFile(account, dune), f);
      await service.removeDownload(account, dune);
      expect(
        downloads.removed.single.toString(),
        'https://abs.example/download/dune?token=t1',
      );
      expect((await store.item('acc1', 'dune')).downloadUri, isNull);
      expect(await service.downloadStatus(account, dune), isNull);
    });
  });

  group('POD-003 the player', () {
    late ScriptedMusicEngine engine;
    late MusicPlayer player;
    late MusicDsp dsp;
    late AbsPlayer abs;
    var now = DateTime.utc(2026, 10, 22, 12);
    var hold = false;

    ServerItem book(
      String id, {
      Duration? at,
      bool played = false,
      String? author,
    }) => ServerItem(
      id: id,
      kind: ServerItemKind.book,
      title: 'Book $id',
      duration: const Duration(minutes: 3),
      playedPosition: at,
      played: played,
      extra: {'author': ?author},
    );

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    AbsPlayer newPlayer() => AbsPlayer(
      player: player,
      engine: engine,
      dsp: dsp,
      service: service,
      holdAtEnd: () => hold,
      clock: () => now,
    );

    setUp(() async {
      now = DateTime.utc(2026, 10, 22, 12);
      hold = false;
      engine = ScriptedMusicEngine();
      player = MusicPlayer(
        engine: engine,
        queues: QueueRepository(db),
        library: MusicLibrary(db),
        files: localMusicFiles(db),
        openTimeout: const Duration(milliseconds: 100),
      );
      await player.init();
      dsp = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
      abs = newPlayer();
    });
    tearDown(() async {
      await abs.dispose();
      await player.dispose();
    });

    test('POD-003 it streams from the address and headers the server '
        'gives, at normal speed, as an episode', () async {
      await abs.play(account, book('b1', author: 'Frank Herbert'));
      final src = engine.opened.last as UriSource;
      expect(src.uri.toString(), 'https://abs.example/audio/b1?token=t1');
      expect(src.headers, {'authorization': 'Bearer t1'});
      expect(player.state.episode?.title, 'Book b1');
      expect(player.state.episode?.show, 'Frank Herbert');
      expect(abs.state.active, isTrue);
      expect(abs.state.speed, 1);
      expect(abs.state.offline, isFalse);
      expect(engine.rates.last, 1);
    });

    test('POD-003 it starts where the server says; a finished item starts '
        'over; a place this device could not report wins', () async {
      await abs.play(account, book('b1', at: const Duration(minutes: 1)));
      expect(engine.current.position, const Duration(minutes: 1));
      await abs.play(
        account,
        book('b2', at: const Duration(minutes: 2), played: true),
      );
      expect(engine.current.position, Duration.zero);

      await store.save(
        'acc1',
        'b3',
        const AbsItemState(position: Duration(seconds: 90), synced: false),
      );
      await abs.play(account, book('b3', at: const Duration(seconds: 30)));
      expect(engine.current.position, const Duration(seconds: 90));
    });

    test("POD-003 once the server has been told, this device's place stands "
        'unless the server says another device changed it since', () async {
      await abs.play(account, book('b1'));
      engine.at(const Duration(seconds: 80));
      await player.pause();
      await settle();
      expect((await store.item('acc1', 'b1')).syncedAt, now.toUtc());
      // The listing is stale (10 s); nothing is newer on the server.
      await abs.play(account, book('b1', at: const Duration(seconds: 10)));
      expect(engine.current.position, const Duration(seconds: 80));
      expect(server.askedSince, now.toUtc());
      // Another device moved on.
      server.changed = const [
        ServerUserData(
          itemId: 'b1',
          played: false,
          position: Duration(minutes: 2),
        ),
      ];
      await abs.play(account, book('b1', at: const Duration(seconds: 10)));
      expect(engine.current.position, const Duration(minutes: 2));
      // Or finished it.
      server.changed = const [ServerUserData(itemId: 'b1', played: true)];
      await abs.play(account, book('b1', at: const Duration(seconds: 10)));
      expect(engine.current.position, Duration.zero);
    });

    test('POD-003 the place goes to the server every 30 seconds while '
        'playing, on pause and on a seek', () async {
      await abs.play(account, book('b1'));
      engine.at(const Duration(seconds: 3));
      await settle();
      expect(server.progress, isEmpty, reason: 'too early to matter');
      now = now.add(const Duration(seconds: 31));
      engine.at(const Duration(seconds: 40));
      await settle();
      expect(server.progress.last, ('b1', const Duration(seconds: 40), false));
      engine.at(const Duration(seconds: 50));
      await settle();
      expect(server.progress.length, 1, reason: 'not again so soon');
      await player.pause();
      await settle();
      expect(server.progress.last.$2, const Duration(seconds: 50));
      await abs.seek(const Duration(seconds: 100));
      expect(server.progress.last.$2, const Duration(seconds: 100));
      expect((await store.item('acc1', 'b1')).synced, isTrue);
    });

    test('POD-003 a server that cannot be reached loses nothing: the place '
        'is kept here, not marked as told, and used next time', () async {
      await abs.play(account, book('b1'));
      server.unreachable = true;
      engine.at(const Duration(seconds: 70));
      await player.pause();
      await settle();
      final s = await store.item('acc1', 'b1');
      expect(s.position, const Duration(seconds: 70));
      expect(s.synced, isFalse);
      server.unreachable = false;
      await abs.dispose();
      abs = newPlayer();
      await abs.play(account, book('b1', at: const Duration(seconds: 10)));
      expect(engine.current.position, const Duration(seconds: 70));
    });

    test("POD-003 speed and skip silence are the item's own; a new item "
        'starts at the last speed', () async {
      await abs.play(account, book('b1'));
      await abs.setSpeed(1.6);
      await abs.setSkipSilence(enabled: true);
      expect(engine.rates.last, 1.6);
      expect(engine.dsp?.skipSilence, isTrue);
      final s = await store.item('acc1', 'b1');
      expect(s.speed, 1.6);
      expect(s.skipSilence, isTrue);
      await abs.play(account, book('b2'));
      expect(abs.state.speed, 1.6);
      expect(abs.state.skipSilence, isFalse);
      expect(engine.dsp?.skipSilence, isFalse);
      await abs.play(account, book('b1'));
      expect(abs.state.skipSilence, isTrue);
    });

    test('POD-003 near the end the server is told it is finished, once, '
        'and a later pause does not undo it', () async {
      await abs.play(account, book('b1'));
      engine.at(const Duration(minutes: 2, seconds: 45));
      await settle();
      expect(server.progress.last, ('b1', const Duration(minutes: 3), true));
      expect(server.played, [('b1', true)]);
      final n = server.progress.length;
      await player.pause();
      await settle();
      expect(server.progress.length, n);
      expect(server.played, hasLength(1));
      expect((await store.item('acc1', 'b1')).position, Duration.zero);
    });

    test('POD-003 when an item ends the next unplayed one of the list '
        'starts; a sleep timer holds it back', () async {
      final list = [book('b1'), book('b2', played: true), book('b3')];
      await abs.play(account, list.first, queue: list);
      engine.finishTrack();
      await settle();
      expect(abs.state.item?.id, 'b3');
      expect((engine.opened.last as UriSource).uri.path, '/audio/b3');
      hold = true;
      await abs.play(account, list.first, queue: list);
      engine.finishTrack();
      await settle();
      expect(abs.state.item?.id, 'b1');
      expect(engine.current.status, PlaybackStatus.ended);
    });

    test('POD-003 an offline copy plays from the file, with no request '
        'for the stream', () async {
      final f = File('${art.path}/b1.m4b');
      await store.save(
        'acc1',
        'b1',
        const AbsItemState(downloadUri: 'https://abs.example/download/b1'),
      );
      downloads.files['https://abs.example/download/b1'] = f;
      await abs.play(account, book('b1'));
      expect((engine.opened.last as UriSource).uri, f.uri);
      expect(abs.state.offline, isTrue);
      expect(server.streamRequests, isEmpty);
    });

    test('POD-003 a server that cannot say where to stream says so and '
        'nothing is opened', () async {
      server.unreachable = true;
      await expectLater(
        abs.play(account, book('b1')),
        throwsA(isA<ServerException>()),
      );
      expect(engine.opened, isEmpty);
      expect(abs.state.active, isFalse);
    });

    test("POD-003 the chapters are the file's own, as the engine reads "
        'them', () async {
      await abs.play(account, book('b1'));
      engine
        ..setChapters(const [
          Chapter(start: Duration.zero, title: 'Intro'),
          Chapter(start: Duration(minutes: 1), title: 'One'),
        ])
        ..at(const Duration(seconds: 10));
      await settle();
      expect(abs.state.chapters.map((c) => c.title), ['Intro', 'One']);
    });

    test('POD-003 playing something else ends Audiobookshelf mode: the '
        'server is told, the speed goes back to normal', () async {
      await MusicSeed(db).song('x/1.mp3', title: 'Song');
      final song = (await MusicLibrary(db).songs()).single;
      await abs.play(account, book('b1'));
      await abs.setSpeed(2);
      engine.at(const Duration(minutes: 1));
      await settle();
      await player.playTracks([song]);
      await settle();
      expect(abs.state.active, isFalse);
      expect(player.state.episode, isNull);
      expect(engine.rates.last, 1);
      expect(server.progress.last.$2, const Duration(minutes: 1));
    });
  });
}

/// A pretend Audiobookshelf server: two libraries, a few books, and a
/// record of what the app told it.
final class FakeServer implements ServerLibrary {
  bool unreachable = false;
  String token = 't1';
  final progress = <(String, Duration, bool)>[];
  final played = <(String, bool)>[];
  final streamRequests = <String>[];

  @override
  ServerAccount get account => throw UnimplementedError();

  void _up() {
    if (unreachable) throw const ServerException(ServerErrorCode.unreachable);
  }

  @override
  Future<String> ping() async {
    _up();
    return 'Audiobookshelf 2.17';
  }

  @override
  Future<List<ServerItem>> libraries() async {
    _up();
    return const [
      ServerItem(id: 'lib1', kind: ServerItemKind.library, title: 'Audiobooks'),
      ServerItem(
        id: 'lib2',
        kind: ServerItemKind.library,
        title: 'Podcasts',
        extra: {'mediaType': 'podcast'},
      ),
    ];
  }

  @override
  Future<ServerPage> browse(
    String parentId, {
    String? cursor,
    int limit = 100,
  }) async {
    _up();
    if (parentId == 'lib1') {
      return cursor == null
          ? const ServerPage(
              items: [
                ServerItem(
                  id: 'dune',
                  kind: ServerItemKind.book,
                  title: 'Dune',
                ),
                ServerItem(
                  id: 'emma',
                  kind: ServerItemKind.book,
                  title: 'Emma',
                ),
              ],
              total: 3,
              nextCursor: 'c2',
            )
          : const ServerPage(
              items: [
                ServerItem(
                  id: 'pers',
                  kind: ServerItemKind.book,
                  title: 'Persuasion',
                ),
              ],
              total: 3,
            );
    }
    return const ServerPage(items: [], total: 0);
  }

  @override
  Future<ServerPage> search(
    String query, {
    Set<ServerItemKind>? kinds,
    int limit = 50,
  }) async {
    _up();
    final all = (await browse('lib1')).items;
    final hits = [
      for (final i in all)
        if (i.title.toLowerCase().contains(query.toLowerCase())) i,
    ];
    return ServerPage(items: hits, total: hits.length);
  }

  @override
  Future<List<ServerItem>> resumeItems({int limit = 20}) async {
    _up();
    return const [
      ServerItem(
        id: 'dune',
        kind: ServerItemKind.book,
        title: 'Dune',
        duration: Duration(hours: 21),
        playedPosition: Duration(hours: 2),
      ),
    ];
  }

  @override
  Future<StreamInfo> streamInfo(
    String itemId, {
    bool allowTranscode = true,
  }) async {
    _up();
    streamRequests.add(itemId);
    return StreamInfo(
      uri: Uri.parse('https://abs.example/audio/$itemId?token=$token'),
      headers: {'authorization': 'Bearer $token'},
    );
  }

  @override
  Future<void> reportProgress(
    String itemId,
    Duration position, {
    bool finished = false,
  }) async {
    _up();
    progress.add((itemId, position, finished));
  }

  @override
  Future<void> setPlayed(String itemId, {required bool played}) async {
    _up();
    this.played.add((itemId, played));
  }

  /// What another device changed since the app last told the server.
  List<ServerUserData> changed = const [];
  DateTime? askedSince;

  @override
  Future<List<ServerUserData>> userData({
    DateTime? changedSince,
    int limit = 500,
  }) async {
    _up();
    askedSince = changedSince;
    return changed;
  }

  @override
  Future<Uri> downloadUri(String itemId) async {
    _up();
    return Uri.parse('https://abs.example/download/$itemId?token=$token');
  }

  @override
  Future<void> close() async {}
}
