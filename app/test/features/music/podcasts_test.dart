import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:mediahro/features/music/podcasts/opml.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

const _rss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>The Show &amp; Co</title>
    <link>https://show.example/</link>
    <description><![CDATA[<p>Talk about <b>things</b>.</p><p>Weekly.</p>]]></description>
    <language>en</language>
    <itunes:author>Ann Host</itunes:author>
    <itunes:image href="/art/cover.jpg"/>
    <item>
      <title>Episode 2</title>
      <guid isPermaLink="false">ep-2</guid>
      <pubDate>Tue, 10 Jun 2025 04:00:00 +0200</pubDate>
      <enclosure url="https://cdn.example/ep2.mp3" length="12345" type="audio/mpeg"/>
      <itunes:duration>1:02:03</itunes:duration>
      <itunes:episode>2</itunes:episode>
      <itunes:season>1</itunes:season>
      <itunes:explicit>yes</itunes:explicit>
      <itunes:image href="https://cdn.example/ep2.jpg"/>
      <content:encoded><![CDATA[<p>Hello&nbsp;<a href="https://x">world</a><br/>line two &amp; more</p>]]></content:encoded>
    </item>
    <item>
      <title>Episode 1</title>
      <pubDate>Mon, 02 Jun 2025 10:30:00 GMT</pubDate>
      <enclosure url="/media/ep1.m4a" type="audio/mp4"/>
      <itunes:duration>2710</itunes:duration>
    </item>
    <item>
      <title>A blog post</title>
      <pubDate>Mon, 26 May 2025 10:30:00 GMT</pubDate>
      <description>No enclosure here.</description>
    </item>
    <item>
      <title>Cover</title>
      <enclosure url="https://cdn.example/cover.png" type="image/png"/>
    </item>
    <item>
      <title>Sneaky</title>
      <enclosure url="file:///etc/passwd" type="audio/mpeg"/>
    </item>
  </channel>
</rss>''';

const _atom = '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Cast</title>
  <subtitle>An atom feed</subtitle>
  <author><name>Bo</name></author>
  <link rel="alternate" href="https://atom.example/"/>
  <logo>https://atom.example/logo.png</logo>
  <entry>
    <title>Entry A</title>
    <id>tag:atom.example,2025:a</id>
    <published>2025-06-01T12:00:00+02:00</published>
    <link rel="enclosure" type="audio/ogg" href="https://atom.example/a.ogg" length="99"/>
    <summary>Short note</summary>
  </entry>
  <entry>
    <title>Entry B</title>
    <id>tag:atom.example,2025:b</id>
    <updated>2025-06-05T00:00:00Z</updated>
    <link rel="enclosure" type="audio/ogg" href="https://atom.example/b.ogg"/>
  </entry>
</feed>''';

void main() {
  group('POD-002 feed parsing', () {
    test('POD-002 RSS: show, episodes newest first, tags decoded, only '
        'playable http(s) enclosures', () {
      final f = parseFeed(_rss, base: Uri.parse('https://show.example/rss'));
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
      final f = parseFeed(_atom);
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
          Uint8List.fromList(utf8.encode(_rss)),
          base: Uri.parse('https://show.example/rss'),
        );
        expect(f.episodes, hasLength(2));
      },
    );

    test('POD-002 an episode survives being stored', () {
      final e = parseFeed(_rss).episodes.first;
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
    late _Net net;
    late _Downloads downloads;
    late PodcastService svc;
    late Directory art;
    var now = DateTime.utc(2026, 10, 22, 12);
    var wifi = true;

    setUp(() async {
      now = DateTime.utc(2026, 10, 22, 12);
      wifi = true;
      db = LibraryDatabase.memory();
      store = PodcastStore(MusicPrefs(db));
      net = _Net();
      downloads = _Downloads();
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
          _rss,
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
        _rss.replaceFirst(
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
      net.serve('https://b.example/f', _atom);
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
        _rss.replaceFirst(
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

    test('POD-002 downloads: the redirect chain is allowed first; deleting '
        'what is played is a per-show choice', () async {
      final show = await svc.subscribe('https://show.example/rss');
      net
        ..redirect(
          'https://cdn.example/ep2.mp3',
          'https://media.example/ep2.mp3',
        )
        ..serve('https://media.example/ep2.mp3', 'AUDIO');
      await svc.download(show, show.episodes.first);
      expect(net.allowed, containsAll(['cdn.example', 'media.example']));
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
      final withNew = _rss.replaceFirst(
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

    test('POD-002 OPML import subscribes to what is new and says what '
        'failed; export lists the subscriptions', () async {
      await svc.subscribe('https://show.example/rss');
      net.serve('https://b.example/f', _atom);
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

  group('POD-002 the network path', () {
    test('POD-002 the body is limited, and a chain that never ends is '
        'cut', () async {
      final net = _Net()
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
        net.http.allowChain(Uri.parse('https://loop.example/a')),
        throwsA(isA<PodcastHttpException>()),
      );
      expect(
        await net.http.allowChain(Uri.parse('https://big.example/f')),
        Uri.parse('https://big.example/f'),
      );
      // Redirects to other schemes are not followed.
      net.redirect('https://odd.example/a', 'file:///etc/passwd');
      final r = await net.http.fetch(Uri.parse('https://odd.example/a'));
      expect(r.status, 302);
    });
  });
}

/// A pretend internet: what each address answers, with redirects, and the
/// hosts the code allowed.
final class _Net {
  final _answers = <String, _Answer>{};
  final allowed = <String>[];
  final requests = <HttpRequestData>[];

  void serve(
    String url,
    String body, {
    int status = 200,
    String? etag,
    String? modified,
    String type = 'application/xml',
    bool blocked = false,
    bool tooLarge = false,
  }) => _answers[url] = _Answer(
    status,
    utf8.encode(body),
    {'content-type': type, 'etag': ?etag, 'last-modified': ?modified},
    blocked: blocked,
    tooLarge: tooLarge,
  );

  void redirect(String from, String to) =>
      _answers[from] = _Answer(302, const [], {'location': to});

  late final http = PodcastHttp(
    allowHost: allowed.add,
    send: (request, {maxRedirects = 5}) async {
      requests.add(request);
      final a = _answers[request.uri.toString()];
      if (a == null) {
        return HttpStreamResponse(404, const {}, Stream.value(const []));
      }
      if (a.blocked) throw NetworkBlocked(request.uri.host, 'off');
      final body = a.tooLarge ? List.filled(25 << 20, 0) : a.body;
      return HttpStreamResponse(
        a.status,
        a.headers,
        Stream.fromIterable([
          for (var i = 0; i < body.length; i += 1 << 20)
            body.sublist(i, (i + (1 << 20)).clamp(0, body.length)),
        ]),
      );
    },
  );
}

final class _Answer {
  _Answer(
    this.status,
    this.body,
    this.headers, {
    this.blocked = false,
    this.tooLarge = false,
  });

  final int status;
  final List<int> body;
  final Map<String, String> headers;
  final bool blocked;
  final bool tooLarge;
}

final class _Downloads implements EpisodeDownloads {
  final enqueued = <(Uri, String, int?)>[];
  final removed = <Uri>[];
  final have = <String>{};

  @override
  Future<void> enqueue(Uri url, {required String title, int? size}) async {
    enqueued.add((url, title, size));
    have.add(url.toString());
  }

  @override
  Future<EpisodeDownload?> status(Uri url) async =>
      have.contains(url.toString())
      ? const EpisodeDownload(DownloadState.queued)
      : null;

  @override
  Future<void> remove(Uri url) async {
    removed.add(url);
    have.remove(url.toString());
  }
}
