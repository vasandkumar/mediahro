import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro/features/music/radio/radio_stations.dart';

import 'podcast_test_support.dart';

/// PRIV-004: a subscription or a station records its host as the user's own
/// choice, only when the user subscribes, adds or imports, and takes it away
/// again with the subscription or the station.
void main() {
  late LibraryDatabase db;
  late _Hosts hosts;

  setUp(() {
    db = LibraryDatabase.memory();
    hosts = _Hosts();
  });
  tearDown(() => db.close());

  group('podcast subscriptions', () {
    late FakeNet net;
    late PodcastService svc;

    setUp(() {
      net = FakeNet()
        ..serve('https://show.example/rss', podcastRss)
        ..serve('https://b.example/f', podcastAtom);
      svc = PodcastService(
        store: PodcastStore(MusicPrefs(db)),
        http: net.http,
        downloads: FakeDownloads(),
        hosts: hosts,
      );
    });
    tearDown(() => svc.dispose());

    test('PRIV-004 subscribing records the feed host under the '
        "subscription, with the show's name", () async {
      final show = await svc.subscribe('https://show.example/rss');
      expect(hosts.entries, [
        ('https://show.example/rss', 'podcast:${show.id}', 'The Show & Co'),
      ]);
      expect(PodcastService.owner(show.id), 'podcast:${show.id}');
    });

    test('PRIV-004 a failed subscription records nothing', () async {
      await expectLater(
        svc.subscribe('https://missing.example/feed'),
        throwsA(isA<PodcastException>()),
      );
      expect(hosts.entries, isEmpty);
    });

    test('PRIV-004 importing an OPML file records the hosts of the feeds '
        'that were subscribed to, not the ones that failed', () async {
      await svc.importOpml(
        '<opml version="2.0"><body> '
        '<outline xmlUrl="https://show.example/rss"/> '
        '<outline xmlUrl="https://b.example/f"/> '
        '<outline xmlUrl="https://gone.example/f"/> '
        '</body></opml>',
      );
      expect(hosts.entries.map((e) => e.$1), [
        'https://show.example/rss',
        'https://b.example/f',
      ]);
    });

    test('PRIV-004 unsubscribing takes the host away; a new title is '
        'recorded when the feed renames the show', () async {
      final show = await svc.subscribe('https://show.example/rss');
      net.serve(
        'https://show.example/rss',
        podcastRss.replaceFirst('The Show &amp; Co', 'Renamed'),
      );
      await svc.refresh(show.id);
      expect(hosts.entries.last.$3, 'Renamed');
      await svc.unsubscribe(show.id);
      expect(hosts.removed, ['podcast:${show.id}']);
    });

    test('PRIV-004 unsubscribing while a refresh is recording a new title '
        'waits for it: the host does not come back', () async {
      final show = await svc.subscribe('https://show.example/rss');
      net.serve(
        'https://show.example/rss',
        podcastRss.replaceFirst('The Show &amp; Co', 'Renamed'),
      );
      hosts
        ..log.clear()
        ..addEntered = Completer<void>()
        ..addGate = Completer<void>();
      final refreshing = svc.refresh(show.id);
      await hosts.addEntered.future;
      final unsubscribing = svc.unsubscribe(show.id);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final gate = hosts.addGate!;
      hosts.addGate = null;
      gate.complete();
      await refreshing;
      await unsubscribing;
      expect(hosts.log, [
        'add:podcast:${show.id}',
        'remove:podcast:${show.id}',
      ]);
      expect(await svc.shows(), isEmpty);
    });

    test('PRIV-004 subscriptions from before hosts were recorded are '
        'recorded once at start', () async {
      final show = await svc.subscribe('https://show.example/rss');
      hosts.entries.clear();
      await svc.syncHosts();
      expect(hosts.entries.single.$2, 'podcast:${show.id}');
      // And the hosts of subscriptions that no longer exist are dropped.
      expect(hosts.pruned.single.$1, 'podcast');
      expect(hosts.pruned.single.$2, {show.id});
    });
  });

  group('radio stations', () {
    RadioStation station(String id, String url, [String name = 'Jazz FM']) =>
        RadioStation(id: id, name: name, url: Uri.parse(url));

    test('PRIV-004 adding a station records its host; renaming updates '
        'the name; deleting removes it', () async {
      final radio = RadioStations(MusicPrefs(db), hosts: hosts);
      await radio.save(station('a', 'http://radio.example.net:8000/live'));
      expect(hosts.entries, [
        ('http://radio.example.net:8000/live', 'radio:a', 'Jazz FM'),
      ]);
      await radio.save(
        station('a', 'http://radio.example.net:8000/live', 'Jazz 2'),
      );
      expect(hosts.entries.last.$3, 'Jazz 2');
      await radio.delete('a');
      expect(hosts.removed, ['radio:a']);
      await radio.dispose();
    });

    test(
      'PRIV-004 an imported station list asks before adding streams on '
      "the listener's own network, and records only what was added",
      () async {
        final radio = RadioStations(
          MusicPrefs(db),
          hosts: hosts,
          nonPublic: (h) async => h == 'inside.example' || h == '10.0.0.4',
        );
        const list = ParsedPlaylist([
          PlaylistEntry('http://one.example/stream', title: 'One'),
          PlaylistEntry('http://10.0.0.4:8000/live', title: 'Box'),
          PlaylistEntry('https://inside.example/hls.m3u8', title: 'Inside'),
        ]);
        var asked = <String>[];
        expect(
          await radio.importPlaylist(
            list,
            confirmLocal: (urls) async {
              asked = urls;
              return false;
            },
          ),
          1,
        );
        expect(asked, [
          'http://10.0.0.4:8000/live',
          'https://inside.example/hls.m3u8',
        ]);
        expect(hosts.entries.map((e) => e.$1), ['http://one.example/stream']);
        // No way to ask: only the public one, as before.
        expect(await radio.importPlaylist(list), 0);
        expect((await radio.all()).map((s) => s.name), ['One']);
        // A yes adds them and their hosts are recorded as the listener's own.
        expect(
          await radio.importPlaylist(list, confirmLocal: (_) async => true),
          2,
        );
        expect(hosts.entries.map((e) => e.$2).toSet().length, 3);
        // A file with nothing inside never asks.
        expect(
          await radio.importPlaylist(
            const ParsedPlaylist([PlaylistEntry('http://new.example/x')]),
            confirmLocal: (_) async => fail('asked about a public stream'),
          ),
          1,
        );
        await radio.dispose();
      },
    );

    test('PRIV-004 an imported station list records the stations that '
        'were added', () async {
      final radio = RadioStations(
        MusicPrefs(db),
        hosts: hosts,
        nonPublic: (_) async => false,
      );
      final added = await radio.importPlaylist(
        const ParsedPlaylist([
          PlaylistEntry('http://one.example/stream', title: 'One'),
          PlaylistEntry('file:///not/a/stream.mp3', title: 'Local'),
        ]),
      );
      expect(added, 1);
      expect(hosts.entries.map((e) => e.$1), ['http://one.example/stream']);
      await radio.dispose();
    });

    test('PRIV-004 stations from before hosts were recorded are recorded '
        'once at start', () async {
      await RadioStations(MusicPrefs(db))
          .save(station('old', 'https://old.example/stream'));
      final radio = RadioStations(MusicPrefs(db), hosts: hosts);
      await radio.syncHosts();
      expect(hosts.entries.single.$2, 'radio:old');
      expect(hosts.pruned.single.$1, 'radio');
      expect(hosts.pruned.single.$2, {'old'});
      await radio.dispose();
    });
  });
}

final class _Hosts implements FeedHostRegistry {
  final entries = <(String, String, String)>[];
  final removed = <String>[];

  /// Every call in order, as `add:<owner>` / `remove:<owner>`.
  final log = <String>[];

  /// Holds [addFeedHost] until it completes.
  Completer<void>? addGate;
  Completer<void> addEntered = Completer<void>();

  @override
  Future<void> addFeedHost(
    Uri url, {
    required String owner,
    required String label,
  }) async {
    log.add('add:$owner');
    if (!addEntered.isCompleted) addEntered.complete();
    await addGate?.future;
    entries.add((url.toString(), owner, label));
  }

  @override
  Future<void> removeFeedOwner(String owner) async {
    log.add('remove:$owner');
    removed.add(owner);
  }

  final pruned = <(String, Set<String>)>[];

  @override
  Future<void> pruneFeedOwners(String prefix, Set<String> existingIds) async =>
      pruned.add((prefix, existingIds));
}
