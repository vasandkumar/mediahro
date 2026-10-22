import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/episode_downloads.dart';
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:mediahro/features/music/podcasts/opml.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'podcast_test_support.dart';

void main() {
  group('POD-002 feed parsing', () {
    test('POD-002 RSS: show, episodes newest first, tags decoded, only '
        'playable http(s) enclosures', () {
      final f = parseFeed(
        podcastRss,
        base: Uri.parse('https://show.example/rss'),
      );
      expect(f.title, 'The Show & Co');
      expect(f.author, 'Ann Host');
      expect(f.description, 'Talk about things.\nWeekly.');
      expect(f.link, 'https://show.example/');
      expect(f.imageUrl, 'https://show.example/art/cover.jpg');
      expect(f.language, 'en');
      expect(f.episodes.map((e) => e.title), ['Episode 2', 'Episode 1']);
      final e2 = f.episodes.first;
      expect(e2.guid, 'ep-2');
      expect(e2.url, 'https://cdn.example/ep2.mp3');
      expect(e2.published, DateTime.utc(2025, 6, 10, 2));
      expect(e2.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(e2.size, 12345);
      expect(e2.mimeType, 'audio/mpeg');
      expect(e2.episode, 2);
      expect(e2.season, 1);
      expect(e2.explicit, isTrue);
      expect(e2.imageUrl, 'https://cdn.example/ep2.jpg');
      expect(e2.description, 'Hello world\nline two & more');
      final e1 = f.episodes.last;
      // No guid: the address stands in; relative addresses resolve.
      expect(e1.guid, 'https://show.example/media/ep1.m4a');
      expect(e1.url, 'https://show.example/media/ep1.m4a');
      expect(e1.duration, const Duration(minutes: 45, seconds: 10));
      expect(e1.explicit, isFalse);
    });

    test('POD-002 Atom: enclosure links, published or updated dates', () {
      final f = parseFeed(podcastAtom);
      expect(f.title, 'Atom Cast');
      expect(f.author, 'Bo');
      expect(f.description, 'An atom feed');
      expect(f.link, 'https://atom.example/');
      expect(f.imageUrl, 'https://atom.example/logo.png');
      expect(f.episodes.map((e) => e.title), ['Entry B', 'Entry A']);
      expect(f.episodes.last.published, DateTime.utc(2025, 6, 1, 10));
      expect(f.episodes.last.size, 99);
      expect(f.episodes.first.guid, 'tag:atom.example,2025:b');
    });

    test('POD-002 dates and durations as feeds write them', () {
      expect(
        parseFeedDate('Tue, 10 Jun 2025 04:00:00 EST'),
        DateTime.utc(2025, 6, 10, 9),
      );
      expect(
        parseFeedDate('10 Jun 25 04:00 PDT'),
        DateTime.utc(2025, 6, 10, 11),
      );
      expect(parseFeedDate('2025-06-10'), DateTime.utc(2025, 6, 10));
      expect(parseFeedDate('2025-06-10T04:00:00-0500'), isNotNull);
      expect(parseFeedDate('yesterday'), isNull);
      expect(parseFeedDate(null), isNull);
      expect(
        parseFeedDuration('45:10'),
        const Duration(minutes: 45, seconds: 10),
      );
      expect(
        parseFeedDuration('3723.5'),
        const Duration(milliseconds: 3723500),
      );
      expect(parseFeedDuration('1:2:3:4'), isNull);
      expect(parseFeedDuration('abc'), isNull);
      expect(parseFeedDuration('0'), isNull);
    });

    test(
      'POD-002 junk is not a feed; a feed with no episodes is a feed',
      () async {
        expect(
          () => parseFeed('<html><body/></html>'),
          throwsA(isA<FeedFormatException>()),
        );
        expect(
          () => parseFeed('not xml at all <'),
          throwsA(isA<FeedFormatException>()),
        );
        expect(
          parseFeed('<rss><channel><title>Empty</title></channel></rss>')
              .episodes,
          isEmpty,
        );
        expect(
          () => parseFeedIsolated(Uint8List(maxFeedBytes + 1)),
          throwsA(isA<FeedFormatException>()),
        );
        final f = await parseFeedIsolated(
          Uint8List.fromList(utf8.encode(podcastRss)),
          base: Uri.parse('https://show.example/rss'),
        );
        expect(f.episodes, hasLength(2));
      },
    );

    test('POD-002 an episode survives being stored', () {
      final e = parseFeed(podcastRss).episodes.first;
      final back = ParsedEpisode.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>,
      )!;
      expect(back.guid, e.guid);
      expect(back.published, e.published);
      expect(back.duration, e.duration);
      expect(back.explicit, isTrue);
      expect(ParsedEpisode.fromJson(const {'guid': 1}), isNull);
    });
  });

  group('POD-002 OPML', () {
    const opml = '''
<?xml version="1.0"?>
<opml version="2.0"><head><title>Subs</title></head><body>
  <outline text="News">
    <outline type="rss" text="Alpha" xmlUrl="https://a.example/feed" htmlUrl="https://a.example/"/>
    <outline type="rss" title="Beta" xmlUrl="http://b.example/rss.xml"/>
  </outline>
  <outline type="rss" text="Alpha again" xmlUrl="https://a.example/feed"/>
  <outline type="rss" text="Local" xmlUrl="file:///x"/>
  <outline type="rss" text="No address"/>
  <outline type="rss" text="A &amp; B" xmlUrl="https://c.example/f?x=1&amp;y=2"/>
</body></opml>''';

    test('POD-002 feeds at any depth, once each, http(s) only', () {
      final f = parseOpml(opml);
      expect(f.map((e) => e.url), [
        'https://a.example/feed',
        'http://b.example/rss.xml',
        'https://c.example/f?x=1&y=2',
      ]);
      expect(f.first.title, 'Alpha');
      expect(f.first.link, 'https://a.example/');
      expect(f[1].title, 'Beta');
      expect(f.last.title, 'A & B');
    });

    test('POD-002 not OPML is no feeds; export round-trips with escaping', () {
      expect(parseOpml('<rss/>'), isEmpty);
      expect(parseOpml('garbage <'), isEmpty);
      final out = buildOpml(parseOpml(opml));
      expect(out, startsWith('<?xml'));
      expect(out, contains('x=1&amp;y=2'));
      expect(out, contains('text="A &amp; B"'));
      final again = parseOpml(out);
      expect(again.map((e) => e.url), parseOpml(opml).map((e) => e.url));
      expect(again.first.title, 'Alpha');
    });
  });

  group('POD-002 subscriptions', () {
    late LibraryDatabase db;
    late PodcastStore store;
    late FakeNet net;
    late FakeDownloads downloads;
    late PodcastService svc;
    late Directory art;
    var now = DateTime.utc(2026, 10, 22, 12);
    var wifi = true;

    setUp(() async {
      now = DateTime.utc(2026, 10, 22, 12);
      wifi = true;
      db = LibraryDatabase.memory();
      store = PodcastStore(MusicPrefs(db));
      net = FakeNet();
      downloads = FakeDownloads();
      art = await Directory.systemTemp.createTemp('c2_pod_art');
      svc = PodcastService(
        store: store,
        http: net.http,
        downloads: downloads,
        artDir: art,
        canDownloadNow: () async => wifi,
        clock: () => now,
      );
      net
        ..serve(
          'https://show.example/rss',
          podcastRss,
          etag: '"v1"',
          modified: 'Tue, 10 Jun 2025 03:00:00 GMT',
        )
        ..serve(
          'https://show.example/art/cover.jpg',
          'JPEGBYTES',
          type: 'image/jpeg',
        );
    });
    tearDown(() async {
      await svc.dispose();
      await db.close();
      try {
        await art.delete(recursive: true);
      } on FileSystemException {
        // Windows may hold a handle briefly.
      }
    });

    test('POD-002 what the listener types becomes a feed address', () {
      expect(
        PodcastService.normalize('show.example/rss')?.toString(),
        'https://show.example/rss',
      );
      expect(
        PodcastService.normalize('  https://a.example/f  ')?.toString(),
        'https://a.example/f',
      );
      expect(
        PodcastService.normalize('feed://a.example/f')?.toString(),
        'https://a.example/f',
      );
      expect(
        PodcastService.normalize('feed:https://a.example/f')?.toString(),
        'https://a.example/f',
      );
      expect(
        PodcastService.normalize('itpc://a.example/f')?.toString(),
        'https://a.example/f',
      );
      expect(
        PodcastService.normalize('http://192.168.1.5:8080/rss')?.toString(),
        'http://192.168.1.5:8080/rss',
      );
      expect(PodcastService.normalize(''), isNull);
      expect(PodcastService.normalize('not a url'), isNull);
      expect(PodcastService.normalize('file:///x'), isNull);
      expect(PodcastService.normalize('nodots'), isNull);
    });

    test('POD-002 subscribing fetches, parses, keeps the show and its '
        'artwork, and lists it', () async {
      final changes = <void>[];
      final sub = svc.changes.listen(changes.add);
      final show = await svc.subscribe('show.example/rss');
      expect(show.title, 'The Show & Co');
      expect(show.episodes, hasLength(2));
      expect(show.etag, '"v1"');
      expect(show.artPath, isNotNull);
      expect(File(show.artPath!).readAsStringSync(), 'JPEGBYTES');
      expect((await svc.shows()).single.id, show.id);
      expect(net.allowed, containsAll(['show.example']));
      await Future<void>.delayed(Duration.zero);
      expect(changes, isNotEmpty);
      await sub.cancel();
      await expectLater(
        svc.subscribe('https://show.example/rss'),
        throwsA(
          isA<PodcastException>()
              .having(
                (e) => e.reason,
                'reason',
                PodcastFailure.alreadySubscribed,
              )
              .having((e) => e.showId, 'id', show.id),
        ),
      );
    });

    test('POD-002 failures have reasons and subscribe nothing', () async {
      Future<PodcastFailure?> reason(String url) async {
        try {
          await svc.subscribe(url);
        } on PodcastException catch (e) {
          return e.reason;
        }
        return null;
      }

      expect(await reason('nope'), PodcastFailure.invalidUrl);
      expect(
        await reason('https://missing.example/feed'),
        PodcastFailure.unreachable,
      );
      net.serve('https://html.example/', '<html><body>hi</body></html>');
      expect(await reason('https://html.example/'), PodcastFailure.notAFeed);
      net
        ..serve('https://blocked.example/feed', '', blocked: true)
        ..serve('https://huge.example/feed', '', tooLarge: true);
      expect(
        await reason('https://blocked.example/feed'),
        PodcastFailure.blocked,
      );
      expect(
        await reason('https://huge.example/feed'),
        PodcastFailure.tooLarge,
      );
      expect(await svc.shows(), isEmpty);
    });

    test('POD-002 redirects are followed hop by hop, each host allowed as '
        'it is reached', () async {
      net
        ..redirect('https://short.example/f', 'https://tracker.example/r?u=1')
        ..redirect('https://tracker.example/r?u=1', 'https://show.example/rss');
      final show = await svc.subscribe('https://short.example/f');
      expect(show.title, 'The Show & Co');
      expect(
        net.allowed,
        containsAll(['short.example', 'tracker.example', 'show.example']),
      );
      expect(show.url, 'https://short.example/f');
    });

    test('POD-002 refresh asks with ETag and Last-Modified; 304 changes '
        'nothing; new episodes are counted', () async {
      final show = await svc.subscribe('https://show.example/rss');
      net.serve('https://show.example/rss', '', status: 304);
      now = now.add(const Duration(hours: 1));
      var r = await svc.refresh(show.id);
      expect(r.ok, isTrue);
      expect(r.added, 0);
      final asked = net.requests.where((q) => q.uri.path == '/rss').last;
      expect(asked.headers['if-none-match'], '"v1"');
      expect(
        asked.headers['if-modified-since'],
        'Tue, 10 Jun 2025 03:00:00 GMT',
      );
      expect((await store.show(show.id))!.lastFetched, now);

      net.serve(
        'https://show.example/rss',
        podcastRss.replaceFirst(
          '<item>',
          '<item><title>Episode 3</title><guid>ep-3</guid> '
              '<pubDate>Tue, 17 Jun 2025 04:00:00 GMT</pubDate> '
              '<enclosure url="https://cdn.example/ep3.mp3" type="audio/mpeg"/></item><item>',
        ),
        etag: '"v2"',
      );
      r = await svc.refresh(show.id);
      expect(r.added, 1);
      final after = (await store.show(show.id))!;
      expect(after.episodes.first.title, 'Episode 3');
      expect(after.etag, '"v2"');
      expect(await svc.unplayedCounts(), {show.id: 3});

      net.serve('https://show.example/rss', '', status: 500);
      expect((await svc.refresh(show.id)).failure, PodcastFailure.unreachable);
      expect((await svc.refresh('nope')).added, 0);
    });

    test('POD-002 refresh all skips shows checked recently', () async {
      final a = await svc.subscribe('https://show.example/rss');
      net.serve('https://b.example/f', podcastAtom);
      final b = await svc.subscribe('https://b.example/f');
      now = now.add(const Duration(hours: 5));
      await store.save(
        (await store.show(b.id))!
            .copyWith(lastFetched: now.subtract(const Duration(minutes: 5))),
      );
      final done = await svc.refreshAll(minAge: const Duration(hours: 1));
      expect(done.map((r) => r.showId), [a.id]);
      expect(await svc.refreshAll(), hasLength(2));
    });

    test('POD-002 played marks and places are kept per episode; an episode '
        'the feed dropped stays while it has a mark', () async {
      final show = await svc.subscribe('https://show.example/rss');
      await svc.markPlayed(show.id, ['ep-2'], played: true);
      await store.saveProgress(
        show.id,
        'https://show.example/media/ep1.m4a',
        const EpisodeProgress(position: Duration(minutes: 3)),
      );
      final list = await svc.episodes(show.id);
      expect(list.map((e) => e.played), [true, false]);
      expect(list.last.progress.position, const Duration(minutes: 3));
      expect(list.last.progress.started, isTrue);
      expect(await svc.unplayedCounts(), {show.id: 1});
      await svc.markPlayed(show.id, ['ep-2'], played: false);
      expect(await svc.unplayedCounts(), {show.id: 2});
      await svc.markAllPlayed(show.id, played: true);
      expect(await svc.unplayedCounts(), {show.id: 0});

      // The feed drops episode 2; it stays because it has a mark.
      net.serve(
        'https://show.example/rss',
        podcastRss.replaceFirst(
          RegExp(r'<item>\s*<title>Episode 2.*?</item>', dotAll: true),
          '',
        ),
      );
      await svc.refresh(show.id);
      expect(
        (await store.show(show.id))!.episodes.map((e) => e.guid),
        contains('ep-2'),
      );
    });

    test('POD-002 oldest-first shows list the other way round', () async {
      final show = await svc.subscribe('https://show.example/rss');
      await svc.configure(show.id, oldestFirst: true);
      expect((await svc.episodes(show.id)).map((e) => e.episode.title), [
        'Episode 1',
        'Episode 2',
      ]);
    });

    test('POD-002 downloads: queued on the download manager; deleting '
        'what is played is a per-show choice', () async {
      final show = await svc.subscribe('https://show.example/rss');
      await svc.download(show, show.episodes.first);
      expect(
        downloads.enqueued.single.$1.toString(),
        'https://cdn.example/ep2.mp3',
      );
      expect(downloads.enqueued.single.$2, 'Episode 2');
      expect(downloads.enqueued.single.$3, 12345);
      expect(
        (await svc.episodes(show.id)).first.download?.state,
        DownloadState.queued,
      );

      await svc.markPlayed(show.id, ['ep-2'], played: true);
      expect(downloads.removed, isEmpty);
      await svc.configure(show.id, deleteWhenPlayed: true);
      await svc.markPlayed(show.id, ['ep-2'], played: true);
      expect(downloads.removed.map((u) => u.toString()), [
        'https://cdn.example/ep2.mp3',
      ]);
    });

    test('POD-002 automatic downloads keep the newest unplayed ones, and '
        'wait for Wi-Fi', () async {
      final show = await svc.subscribe('https://show.example/rss');
      await svc.configure(show.id, autoDownload: 1);
      final withNew = podcastRss.replaceFirst(
        '<item>',
        '<item><title>Episode 3</title><guid>ep-3</guid> '
            '<pubDate>Tue, 17 Jun 2025 04:00:00 GMT</pubDate> '
            '<enclosure url="https://cdn.example/ep3.mp3" type="audio/mpeg"/></item><item>',
      );
      wifi = false;
      net.serve('https://show.example/rss', withNew, etag: '"v2"');
      await svc.refresh(show.id);
      expect(downloads.enqueued, isEmpty);

      wifi = true;
      final withNewer = withNew.replaceFirst(
        '<item>',
        '<item><title>Episode 4</title><guid>ep-4</guid> '
            '<pubDate>Tue, 24 Jun 2025 04:00:00 GMT</pubDate> '
            '<enclosure url="https://cdn.example/ep4.mp3" type="audio/mpeg"/></item><item>',
      );
      net.serve('https://show.example/rss', withNewer, etag: '"v3"');
      await svc.refresh(show.id);
      expect(downloads.enqueued.map((e) => e.$1.toString()), [
        'https://cdn.example/ep4.mp3',
      ]);
    });

    test('POD-002 unsubscribing removes the show, its marks, its downloads '
        'and its artwork', () async {
      final show = await svc.subscribe('https://show.example/rss');
      await svc.markPlayed(show.id, ['ep-2'], played: true);
      downloads.have.add('https://cdn.example/ep2.mp3');
      final artPath = show.artPath!;
      await svc.unsubscribe(show.id);
      expect(await svc.shows(), isEmpty);
      expect(await store.progress(show.id), isEmpty);
      expect(File(artPath).existsSync(), isFalse);
      expect(
        downloads.removed.map((u) => u.toString()),
        contains('https://cdn.example/ep2.mp3'),
      );
    });

    test('POD-002 unsubscribing while a refresh is in flight: the result '
        'is dropped, nothing comes back, nothing is downloaded', () async {
      final show = await svc.subscribe('https://show.example/rss');
      await svc.configure(show.id, autoDownload: 2);
      final artPath = show.artPath!;
      final withNew = podcastRss.replaceFirst(
        '<item>',
        '<item><title>Episode 3</title><guid>ep-3</guid> '
            '<pubDate>Tue, 17 Jun 2025 04:00:00 GMT</pubDate> '
            '<enclosure url="https://cdn.example/ep3.mp3" type="audio/mpeg"/></item><item>',
      );
      net.serve('https://show.example/rss', withNew, etag: '"v2"');
      final gate = net.gates['https://show.example/rss'] = Completer<void>();
      final refreshing = svc.refresh(show.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await svc.unsubscribe(show.id);
      gate.complete();
      final r = await refreshing;
      expect(r.added, 0);
      expect(await svc.shows(), isEmpty);
      expect(await store.show(show.id), isNull);
      expect(downloads.enqueued, isEmpty);
      expect(File(artPath).existsSync(), isFalse);
      expect(net.openChains, 0);
    });

    test('POD-002 unsubscribing in the middle of the step that writes a '
        'refresh back waits for it, then removes everything', () async {
      final show = await svc.subscribe('https://show.example/rss');
      await svc.configure(show.id, autoDownload: 2);
      downloads.have.add('https://cdn.example/ep2.mp3');
      final withNew = podcastRss.replaceFirst(
        '<item>',
        '<item><title>Episode 3</title><guid>ep-3</guid> '
            '<pubDate>Tue, 17 Jun 2025 04:00:00 GMT</pubDate> '
            '<enclosure url="https://cdn.example/ep3.mp3" type="audio/mpeg"/></item><item>',
      );
      net.serve('https://show.example/rss', withNew, etag: '"v2"');
      // The refresh has read the show and is looking at what is downloaded
      // (an await inside the read-then-write step) when the listener
      // unsubscribes.
      downloads
        ..statusAsked = Completer<void>()
        ..statusGate = Completer<void>();
      final refreshing = svc.refresh(show.id);
      await downloads.statusAsked.future;
      final unsubscribing = svc.unsubscribe(show.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final gate = downloads.statusGate!;
      downloads.statusGate = null;
      gate.complete();
      await refreshing;
      await unsubscribing;
      expect(await svc.shows(), isEmpty);
      expect(await store.show(show.id), isNull);
      expect(downloads.enqueued, isEmpty);
      expect(downloads.have, isEmpty);
    });

    test(
      'POD-002 a setting changed during the write-back step is not lost',
      () async {
        final show = await svc.subscribe('https://show.example/rss');
        await svc.configure(show.id, autoDownload: 2);
        final withNew = podcastRss.replaceFirst(
          '<item>',
          '<item><title>Episode 3</title><guid>ep-3</guid> '
              '<pubDate>Tue, 17 Jun 2025 04:00:00 GMT</pubDate> '
              '<enclosure url="https://cdn.example/ep3.mp3" type="audio/mpeg"/></item><item>',
        );
        net.serve('https://show.example/rss', withNew, etag: '"v2"');
        downloads
          ..statusAsked = Completer<void>()
          ..statusGate = Completer<void>();
        final refreshing = svc.refresh(show.id);
        await downloads.statusAsked.future;
        final configuring = svc.configure(show.id, speed: 1.75);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final gate = downloads.statusGate!;
        downloads.statusGate = null;
        gate.complete();
        await refreshing;
        await configuring;
        expect((await store.show(show.id))!.speed, 1.75);
        expect((await store.show(show.id))!.episodes.first.guid, 'ep-3');
      },
    );

    test('POD-002 two subscriptions to one feed at the same time make one '
        'subscription', () async {
      final both = await Future.wait([
        svc
            .subscribe('https://show.example/rss')
            .then<Object>((s) => s, onError: (Object e) => e),
        svc
            .subscribe('https://show.example/rss')
            .then<Object>((s) => s, onError: (Object e) => e),
      ]);
      expect(both.whereType<PodcastShow>(), hasLength(1));
      expect(both.whereType<PodcastException>(), hasLength(1));
      expect(await svc.shows(), hasLength(1));
    });

    test("POD-002 an OPML file that lists addresses on the listener's own "
        'network asks first; public ones import as usual', () async {
      net
        ..serve('https://b.example/f', podcastAtom)
        ..serve('http://192.168.1.9/rss', podcastRss)
        ..serve('http://localhost:8080/f', podcastRss);
      const opml = '''
<opml version="2.0"><body>
  <outline xmlUrl="https://b.example/f"/>
  <outline xmlUrl="http://192.168.1.9/rss"/>
  <outline xmlUrl="http://localhost:8080/f"/>
</body></opml>''';
      // No answer, or no: the public one only.
      var asked = <String>[];
      // A name that points inside, or cannot be checked, is asked about too.
      net.dns['sneaky.example'] = [InternetAddress('10.9.9.9')];
      net.dns['unknown.example'] = [];
      final named = await svc.importOpml(
        '<opml version="2.0"><body> '
        '<outline xmlUrl="https://sneaky.example/f"/> '
        '<outline xmlUrl="https://unknown.example/f"/> '
        '<outline xmlUrl="https://b.example/f"/> '
        '</body></opml>',
        confirmLocal: (urls) async {
          expect(urls, [
            'https://sneaky.example/f',
            'https://unknown.example/f',
          ]);
          return false;
        },
      );
      expect(named.declined, hasLength(2));
      expect(named.added, 1);
      await svc.unsubscribe(PodcastStore.idOf('https://b.example/f'));
      final declined = await svc.importOpml(
        opml,
        confirmLocal: (urls) async {
          asked = urls;
          return false;
        },
      );
      expect(asked, ['http://192.168.1.9/rss', 'http://localhost:8080/f']);
      expect(declined.added, 1);
      expect(declined.declined, asked);
      expect((await svc.shows()).map((s) => s.url), ['https://b.example/f']);
      expect(
        net.requests.map((r) => r.uri.host),
        isNot(contains('192.168.1.9')),
      );
      final noCallback = await svc.importOpml(opml);
      expect(noCallback.declined, hasLength(2));
      expect(await svc.shows(), hasLength(1));
      // Yes: they are added, and typing their address is theirs to do.
      final yes = await svc.importOpml(opml, confirmLocal: (_) async => true);
      expect(yes.added, 2);
      expect(yes.declined, isEmpty);
      expect(await svc.shows(), hasLength(3));
      // A file with only public feeds never asks.
      final fresh = await svc.importOpml(
        '<opml version="2.0"><body><outline xmlUrl="https://b.example/f"/></body></opml>',
        confirmLocal: (_) async => fail('asked about a public feed'),
      );
      expect(fresh.alreadySubscribed, 1);
    });

    test('POD-002 a refresh keeps the choices made while it was in '
        'flight', () async {
      final show = await svc.subscribe('https://show.example/rss');
      net.serve('https://show.example/rss', podcastRss, etag: '"v2"');
      final gate = net.gates['https://show.example/rss'] = Completer<void>();
      final refreshing = svc.refresh(show.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await svc.configure(show.id, oldestFirst: true, speed: 1.5);
      gate.complete();
      await refreshing;
      final now = (await store.show(show.id))!;
      expect(now.oldestFirst, isTrue);
      expect(now.speed, 1.5);
    });

    test("POD-002 a feed on the listener's own network may use that host; "
        'any other private address it names is refused', () async {
      net
        ..serve('http://192.168.1.9/rss', podcastRss)
        ..serve(
          'http://192.168.1.9/rss2',
          podcastRss.replaceAll(
            'https://show.example/art/cover.jpg',
            'http://10.0.0.7/cover.jpg',
          ),
        )
        ..serve('http://10.0.0.7/cover.jpg', 'NOPE', type: 'image/jpeg');
      final show = await svc.subscribe('http://192.168.1.9/rss');
      expect(show.title, 'The Show & Co');
      final other = await svc.subscribe('http://192.168.1.9/rss2');
      expect(other.artPath, isNull);
      expect(net.requests.map((r) => r.uri.host), isNot(contains('10.0.0.7')));
    });

    test("POD-002 a public feed host that is repointed at the listener's "
        'network is refused: it gets the lookup like any other hop', () async {
      net.dns['show.example'] = [InternetAddress('192.168.1.1')];
      await expectLater(
        svc.subscribe('https://show.example/rss'),
        throwsA(
          isA<PodcastException>().having(
            (e) => e.reason,
            'reason',
            PodcastFailure.privateAddress,
          ),
        ),
      );
      expect(net.requests, isEmpty);
      // A name that cannot be resolved is not followed either.
      net.dns['show.example'] = [];
      await expectLater(
        svc.subscribe('https://show.example/rss'),
        throwsA(isA<PodcastException>()),
      );
      expect(net.requests, isEmpty);
      // A feed the listener typed on their own network keeps working, as a
      // `.local` name does.
      net
        ..serve('http://nas.local/rss', podcastRss)
        ..dns.remove('show.example');
      expect((await svc.subscribe('http://nas.local/rss')).title, isNotEmpty);
    });

    test('POD-002 the feed host trusted for an episode is only a private one '
        'the listener gave', () async {
      net
        ..serve('http://192.168.1.9/rss', podcastRss)
        ..serve('http://192.168.1.9/art/cover.jpg', 'x')
        ..serve('https://b.example/f', podcastAtom);
      final local = await svc.subscribe('http://192.168.1.9/rss');
      final online = await svc.subscribe('https://b.example/f');
      expect(await store.feedHostFor(Uri.parse(local.episodes.first.url)), {
        '192.168.1.9',
      });
      expect(
        await store.feedHostFor(Uri.parse(online.episodes.first.url)),
        isEmpty,
      );
      expect(
        await store.feedHostFor(Uri.parse('https://nowhere.example/x')),
        isEmpty,
      );
    });

    test('POD-002 a public feed cannot send the app to the LAN: a redirect '
        'to a private address is refused', () async {
      net
        ..redirect('https://short.example/f', 'http://192.168.1.5/rss')
        ..serve('http://192.168.1.5/rss', podcastRss);
      await expectLater(
        svc.subscribe('https://short.example/f'),
        throwsA(
          isA<PodcastException>().having(
            (e) => e.reason,
            'reason',
            PodcastFailure.privateAddress,
          ),
        ),
      );
      expect(
        net.requests.map((r) => r.uri.host),
        isNot(contains('192.168.1.5')),
      );
      expect(net.allowed, isNot(contains('192.168.1.5')));
      expect(await svc.shows(), isEmpty);
    });

    test('POD-002 a picture still open (it is on screen) does not stop '
        'unsubscribing', () async {
      final show = await svc.subscribe('https://show.example/rss');
      final open = await File(show.artPath!).open();
      addTearDown(open.close);
      // On Windows the file cannot be deleted while it is open; elsewhere it
      // can. Either way the subscription is gone.
      await svc.unsubscribe(show.id);
      expect(await svc.shows(), isEmpty);
      expect(await store.show(show.id), isNull);
      expect(await store.progress(show.id), isEmpty);
    });

    test('POD-002 OPML import subscribes to what is new and says what '
        'failed; export lists the subscriptions', () async {
      await svc.subscribe('https://show.example/rss');
      net.serve('https://b.example/f', podcastAtom);
      final progress = <(int, int)>[];
      final r = await svc.importOpml('''
<opml version="2.0"><body>
  <outline xmlUrl="https://show.example/rss"/>
  <outline xmlUrl="https://b.example/f"/>
  <outline xmlUrl="https://gone.example/f"/>
</body></opml>''', onProgress: (d, t) => progress.add((d, t)));
      expect(r.added, 1);
      expect(r.alreadySubscribed, 1);
      expect(r.failed, ['https://gone.example/f']);
      expect(progress.last, (3, 3));
      final out = await svc.exportOpml();
      expect(parseOpml(out).map((e) => e.url), [
        'https://show.example/rss',
        'https://b.example/f',
      ]);
      expect(parseOpml(out).first.title, 'The Show & Co');
    });
  });

  group('POD-002 request allowances', () {
    test('POD-002 each request chain is allowed while it runs and not '
        'after; nothing stays on the session', () async {
      final net = FakeNet()
        ..redirect('https://short.example/f', 'https://tracker.example/r')
        ..redirect('https://tracker.example/r', 'https://show.example/rss')
        ..serve('https://show.example/rss', podcastRss);
      final res = await net.http.fetch(Uri.parse('https://short.example/f'));
      expect(res.status, 200);
      expect(net.allowed, ['short.example', 'tracker.example', 'show.example']);
      expect(net.openChains, 0);
      expect(net.openHosts, isEmpty);
      // A request that fails ends its allowance too.
      net.serve('https://blocked.example/f', 'x', blocked: true);
      await expectLater(
        net.http.fetch(Uri.parse('https://blocked.example/f')),
        throwsA(anything),
      );
      expect(net.openChains, 0);
    });

    test("POD-002 the listener's own network is refused whatever the "
        'address looks like, unless it is the host they gave', () async {
      final net = FakeNet()..serve('http://localhost:8080/f', 'x');
      for (final target in const [
        'http://192.168.1.5/e.mp3',
        'http://127.0.0.1/e.mp3',
        'http://127.1/e.mp3',
        'http://2130706433/e.mp3',
        'http://0x7f000001/e.mp3',
        'http://0177.0.0.1/e.mp3',
        'http://0.0.0.0/e.mp3',
        'http://169.254.169.254/e.mp3',
        'http://10.0.0.1./e.mp3',
        'http://100.64.0.9/e.mp3',
        'http://localhost./e.mp3',
        'http://nas.local/e.mp3',
        'http://router/e.mp3',
        'http://[::1]/e.mp3',
        'http://[::]/e.mp3',
        'http://[::ffff:192.168.1.5]/e.mp3',
        'http://[::ffff:8.8.8.8]/e.mp3',
        'http://[fd00::1]/e.mp3',
        'http://[fe80::1]/e.mp3',
      ]) {
        net.redirect('https://cdn.example/e.mp3', target);
        await expectLater(
          net.http.fetch(Uri.parse('https://cdn.example/e.mp3')),
          throwsA(
            isA<PodcastHttpException>().having(
              (e) => e.reason,
              'reason',
              'private address',
            ),
          ),
          reason: target,
        );
      }
      expect(net.requests.map((r) => r.uri.host), everyElement('cdn.example'));
      expect(net.openChains, 0);
      // The host the listener gave is theirs to use, and only that one.
      final typed = await net.http.fetch(
        Uri.parse('http://localhost:8080/f'),
        trusted: {'localhost'},
      );
      expect(typed.status, 200);
      net.redirect('http://localhost:8080/f', 'http://192.168.1.5/e.mp3');
      await expectLater(
        net.http.fetch(
          Uri.parse('http://localhost:8080/f'),
          trusted: {'localhost'},
        ),
        throwsA(isA<PodcastHttpException>()),
      );
    });

    test('POD-002 a name that points inside is refused too, on any of its '
        'addresses', () async {
      final net = FakeNet()
        ..dns['inside.example'] = [InternetAddress('10.1.2.3')]
        ..dns['mixed.example'] = [
          InternetAddress('93.184.216.34'),
          InternetAddress('192.168.0.9'),
        ]
        ..dns['v6.example'] = [InternetAddress('fd12::1')]
        ..serve('https://outside.example/e', 'ok');
      for (final host in const ['inside', 'mixed', 'v6']) {
        net.redirect('https://cdn.example/e', 'https://$host.example/e');
        await expectLater(
          net.http.fetch(Uri.parse('https://cdn.example/e')),
          throwsA(isA<PodcastHttpException>()),
          reason: host,
        );
      }
      net.redirect('https://cdn.example/e', 'https://outside.example/e');
      expect(
        (await net.http.fetch(Uri.parse('https://cdn.example/e'))).status,
        200,
      );
    });

    test('POD-002 a file looks a host up once, not for every block', () async {
      final net = FakeNet();
      final bytes = List<int>.generate(3 << 20, (i) => i & 255);
      net.serveBytes('https://cdn.example/a.mp3', bytes);
      final file = await net.http.openFile(
        Uri.parse('https://cdn.example/a.mp3'),
      );
      for (var i = 0; i < 6; i++) {
        final got = await file.read(i * (300 << 10), 1000);
        expect(got, bytes.sublist(i * (300 << 10), i * (300 << 10) + 1000));
      }
      expect(net.lookups, ['cdn.example']);
      await file.close();
    });

    test(
      'POD-002 a read of a megabyte is one request, not four blocks',
      () async {
        final net = FakeNet();
        final bytes = List<int>.generate(3 << 20, (i) => (i * 7) & 255);
        net.serveBytes('https://cdn.example/a.mp3', bytes);
        final file = await net.http.openFile(
          Uri.parse('https://cdn.example/a.mp3'),
        );
        final before = net.requests.length;
        expect(
          await file.read(100, 1 << 20),
          bytes.sublist(100, 100 + (1 << 20)),
        );
        expect(net.requests.length - before, 1);
        expect(
          net.requests.last.headers['range'],
          'bytes=100-${100 + (1 << 20) - 1}',
        );
        await file.close();
      },
    );

    test('POD-002 a server without ranges is read as one stream: later and '
        'repeated reads work, going back starts it again', () async {
      final net = FakeNet();
      final bytes = List<int>.generate(700 << 10, (i) => (i * 13) & 255);
      net.serveBytes('https://cdn.example/a.mp3', bytes, ranges: false);
      final file = await net.http.openFile(
        Uri.parse('https://cdn.example/a.mp3'),
      );
      expect(file.isSeekable, isFalse);
      expect(await file.length(), bytes.length);
      final probe = net.requests.length;
      expect(await file.read(0, 256 << 10), bytes.sublist(0, 256 << 10));
      expect(
        await file.read(256 << 10, 256 << 10),
        bytes.sublist(256 << 10, 512 << 10),
      );
      // Forward past what was read, and the end of the file.
      expect(await file.read(600 << 10, 500 << 10), bytes.sublist(600 << 10));
      // The same stream served all of that.
      expect(net.requests.length - probe, 1);
      // Back to the start: the stream begins again.
      expect(await file.read(10, 100), bytes.sublist(10, 110));
      expect(net.requests.length - probe, 2);
      expect(net.lookups, ['cdn.example']);
      await file.close();
    });

    test('POD-002 an episode file holds its allowance for as long as it is '
        'open, and no longer', () async {
      final net = FakeNet()
        ..redirect('https://cdn.example/a.mp3', 'https://media.example/a.mp3')
        ..handlers['https://media.example/a.mp3'] = (r) {
          final range = RegExp(r'bytes=(\d+)-(\d+)')
              .firstMatch(r.headers['range']!)!;
          final from = int.parse(range.group(1)!);
          final to = int.parse(range.group(2)!).clamp(0, 9);
          return FakeNet.response(
            206,
            utf8.encode('0123456789').sublist(from, to + 1),
            {'content-range': 'bytes $from-$to/10'},
          );
        };
      final file = await net.http.openFile(
        Uri.parse('https://cdn.example/a.mp3'),
      );
      expect(file.uri, Uri.parse('https://cdn.example/a.mp3'));
      expect(await file.length(), 10);
      expect(file.isSeekable, isTrue);
      expect(net.openHosts, {'cdn.example', 'media.example'});
      expect(utf8.decode(await file.read(2, 4)), '2345');
      expect(utf8.decode(await file.read(7, 50)), '789');
      await file.close();
      expect(net.openHosts, isEmpty);
      expect(net.openChains, 0);
      await expectLater(file.read(0, 1), throwsA(isA<VirtualFileException>()));
    });

    test('POD-002 a redirect that only shows up on a later read is checked '
        'like the first one', () async {
      final net = FakeNet();
      var requests = 0;
      net.handlers['https://cdn.example/a.mp3'] = (r) {
        requests++;
        // The probe is fine; a later read is sent inside the network.
        if (requests == 1) {
          return FakeNet.response(206, [48], {'content-range': 'bytes 0-0/10'});
        }
        return FakeNet.response(302, const [], {
          'location': 'http://10.0.0.1/a.mp3',
        });
      };
      net.serve('http://10.0.0.1/a.mp3', 'INSIDE');
      final file = await net.http.openFile(
        Uri.parse('https://cdn.example/a.mp3'),
      );
      await expectLater(
        file.read(0, 4),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.permissionDenied,
          ),
        ),
      );
      expect(net.requests.map((r) => r.uri.host), isNot(contains('10.0.0.1')));
      await file.close();
      expect(net.openChains, 0);
    });

    test('POD-002 a read that redirects to another public host is followed, '
        'one checked hop at a time', () async {
      final net = FakeNet();
      net.handlers['https://cdn.example/a.mp3'] = (r) {
        if (r.headers['range'] == 'bytes=0-0') {
          return FakeNet.response(206, [48], {'content-range': 'bytes 0-0/10'});
        }
        return FakeNet.response(302, const [], {
          'location': 'https://other.example/a.mp3',
        });
      };
      net.handlers['https://other.example/a.mp3'] = (r) => FakeNet.response(
        206,
        utf8.encode('0123456789'),
        {'content-range': 'bytes 0-9/10'},
      );
      final file = await net.http.openFile(
        Uri.parse('https://cdn.example/a.mp3'),
      );
      expect(utf8.decode(await file.read(0, 10)), '0123456789');
      expect(net.allowed, contains('other.example'));
      await file.close();
    });

    test("POD-002 an episode file opened on a feed's own host may reach it; "
        'other private hosts are permission denied', () async {
      final net = FakeNet();
      net.handlers['http://192.168.1.9/a.mp3'] = (r) =>
          FakeNet.response(206, [48], {'content-range': 'bytes 0-0/10'});
      net
        ..redirect('http://192.168.1.9/b.mp3', 'http://192.168.1.77/b.mp3')
        ..redirect('https://cdn.example/c.mp3', 'http://192.168.1.9/a.mp3');
      final fs = HttpUrlFileSystem(
        net.http,
        trustedFor: (u) async => {'192.168.1.9'},
      );
      final file = await fs.open(Uri.parse('http://192.168.1.9/a.mp3'));
      await file.close();
      for (final u in const [
        'http://192.168.1.9/b.mp3',
        'http://192.168.1.77/b.mp3',
      ]) {
        await expectLater(
          fs.open(Uri.parse(u)),
          throwsA(
            isA<VirtualFileException>().having(
              (e) => e.error,
              'error',
              VirtualFileError.permissionDenied,
            ),
          ),
          reason: u,
        );
      }
      // Trust belongs to the feed: the same episode on a public feed gets
      // none.
      final publicFeed = HttpUrlFileSystem(
        net.http,
        trustedFor: (u) async => const {},
      );
      await expectLater(
        publicFeed.open(Uri.parse('http://192.168.1.9/a.mp3')),
        throwsA(isA<VirtualFileException>()),
      );
      expect(net.openChains, 0);
    });
  });

  group('POD-002 podcast downloads', () {
    test('PRIV-004 removing an episode (or its show, or its host) closes the '
        'files still open for it: the next read fails', () async {
      final net = FakeNet();
      final bytes = List<int>.generate(600 << 10, (i) => i & 255);
      net
        ..serveBytes('https://cdn.example/a.mp3', bytes)
        ..serveBytes('https://cdn.example/b.mp3', bytes);
      final fs = HttpUrlFileSystem(net.http, trustedFor: (_) async => const {});
      final a = Uri.parse('https://cdn.example/a.mp3');
      final b = Uri.parse('https://cdn.example/b.mp3');
      final streamA = await fs.open(a);
      final downloadA = await fs.open(podcastDownloadUri(a));
      final streamB = await fs.open(b);
      expect(await streamA.read(0, 10), bytes.sublist(0, 10));
      expect(net.openChains, 3);
      await fs.revoke(a);
      for (final f in [streamA, downloadA]) {
        await expectLater(f.read(0, 10), throwsA(isA<VirtualFileException>()));
      }
      expect(net.openChains, 1);
      // Another episode goes on.
      expect(await streamB.read(0, 10), bytes.sublist(0, 10));
      await streamB.close();
      expect(net.openChains, 0);
      // Revoking what is not open, or twice, is harmless.
      await fs.revoke(a);
      await fs.revoke(b);
    });

    test('PRIV-004 ManagerEpisodeDownloads.remove closes a stream of that '
        'episode', () async {
      final db = LibraryDatabase.memory();
      final dir = Directory.systemTemp.createTempSync('c2_pod_rv');
      addTearDown(() async {
        await db.close();
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best effort.
        }
      });
      final net = FakeNet()
        ..serveBytes('https://cdn.example/a.mp3', List<int>.filled(4000, 7));
      final fs = HttpUrlFileSystem(net.http, trustedFor: (_) async => const {});
      final downloads = ManagerEpisodeDownloads(
        manager: DownloadManager(
          db: db,
          directory: Directory('${dir.path}/d'),
          opener: fs.open,
        ),
        mounts: MountedFileSystems(),
        fileSystem: fs,
      );
      final url = Uri.parse('https://cdn.example/a.mp3');
      final stream = await downloads.openStream(url);
      expect(await stream.read(0, 4), [7, 7, 7, 7]);
      await downloads.remove(url);
      await expectLater(
        stream.read(0, 4),
        throwsA(isA<VirtualFileException>()),
      );
      expect(net.openChains, 0);
      await downloads.manager.dispose();
    });

    test('POD-002 a download is opened by the podcast file system only, '
        'never by a source the listener added for the same host', () async {
      final db = LibraryDatabase.memory();
      final dir = Directory.systemTemp.createTempSync('c2_pod_dl');
      addTearDown(() async {
        await db.close();
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best effort.
        }
      });
      final net = FakeNet();
      final bytes = List<int>.generate(300 << 10, (i) => (i * 3) & 255);
      net.serveBytes('https://cdn.example/dl/e.mp3', bytes);
      final mounts = MountedFileSystems();
      final user = _UserShare();
      // The listener's own WebDAV source on the very same host.
      mounts.mount(Uri.parse('https://cdn.example'), user);
      final manager = DownloadManager(
        db: db,
        directory: Directory('${dir.path}/downloads'),
        opener: (uri) => mounts.forUri(uri).open(uri),
        concurrency: 1,
      );
      final downloads = ManagerEpisodeDownloads(
        manager: manager,
        mounts: mounts,
        fileSystem: HttpUrlFileSystem(
          net.http,
          trustedFor: (_) async => const {},
        ),
      );
      final url = Uri.parse('https://cdn.example/dl/e.mp3');
      await downloads.enqueue(url, title: 'E', size: bytes.length);
      EpisodeDownload? d;
      for (var i = 0; i < 100; i++) {
        d = await downloads.status(url);
        if (d != null && d.done) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(d?.done, isTrue, reason: '${d?.state}');
      expect(d!.file!.readAsBytesSync(), bytes);
      expect(user.opened, isEmpty, reason: "the listener's source was used");
      final row = (await db.select(db.downloads).get()).single;
      expect(row.remoteUri, 'podcast-https://cdn.example/dl/e.mp3');
      expect(podcastEpisodeUri(Uri.parse(row.remoteUri)), url);
      expect(podcastEpisodeUri(url), isNull);
      // Removing it goes by the episode's own address.
      await downloads.remove(url);
      expect(await downloads.status(url), isNull);
      await manager.dispose();
    });

    test('POD-002 a download whose address leads inside the network fails '
        'and is not fetched', () async {
      final db = LibraryDatabase.memory();
      final dir = Directory.systemTemp.createTempSync('c2_pod_dl2');
      addTearDown(() async {
        await db.close();
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best effort.
        }
      });
      final net = FakeNet()
        ..redirect('https://cdn.example/e.mp3', 'http://10.0.0.5/e.mp3')
        ..serve('http://10.0.0.5/e.mp3', 'INSIDE');
      final mounts = MountedFileSystems();
      final manager = DownloadManager(
        db: db,
        directory: Directory('${dir.path}/downloads'),
        opener: (uri) => mounts.forUri(uri).open(uri),
        concurrency: 1,
      );
      final downloads = ManagerEpisodeDownloads(
        manager: manager,
        mounts: mounts,
        fileSystem: HttpUrlFileSystem(
          net.http,
          trustedFor: (_) async => const {},
        ),
      );
      final url = Uri.parse('https://cdn.example/e.mp3');
      await downloads.enqueue(url, title: 'E');
      EpisodeDownload? d;
      for (var i = 0; i < 100; i++) {
        d = await downloads.status(url);
        if (d != null && d.state == DownloadState.failed) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(d?.state, DownloadState.failed);
      expect(net.requests.map((r) => r.uri.host), everyElement('cdn.example'));
      await manager.dispose();
    });
  });

  group('POD-002 the network path', () {
    test('POD-002 the body is limited, and a chain that never ends is '
        'cut', () async {
      final net = FakeNet()
        ..serve('https://big.example/f', 'x' * 100)
        ..redirect('https://loop.example/a', 'https://loop.example/b')
        ..redirect('https://loop.example/b', 'https://loop.example/a');
      await expectLater(
        net.http.fetch(Uri.parse('https://big.example/f'), maxBytes: 50),
        throwsA(isA<PodcastHttpException>()),
      );
      await expectLater(
        net.http.fetch(Uri.parse('https://loop.example/a')),
        throwsA(isA<PodcastHttpException>()),
      );
      await expectLater(
        net.http.openFile(Uri.parse('https://loop.example/a')),
        throwsA(isA<VirtualFileException>()),
      );
      expect(net.openChains, 0);
      // Redirects to other schemes are not followed.
      net.redirect('https://odd.example/a', 'file:///etc/passwd');
      final r = await net.http.fetch(Uri.parse('https://odd.example/a'));
      expect(r.status, 302);
    });
  });
}

/// A source the listener added that serves a host, and says if it was used.
final class _UserShare implements VirtualFileSystem {
  final opened = <Uri>[];

  @override
  Set<String> get schemes => const {'https'};

  @override
  Set<VirtualFsCapability> get capabilities => const {};

  @override
  Future<VirtualFile> open(Uri uri) async {
    opened.add(uri);
    throw VirtualFileException(VirtualFileError.io, uri, 'used');
  }

  @override
  Future<VirtualEntry> stat(Uri uri) => throw UnimplementedError();

  @override
  Stream<VirtualEntry> list(Uri directory) => const Stream.empty();
}
