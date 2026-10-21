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
        'subscription, with the show\'s name', () async {
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
        '<opml version="2.0"><body>'
        '<outline xmlUrl="https://show.example/rss"/>'
        '<outline xmlUrl="https://b.example/f"/>'
        '<outline xmlUrl="https://gone.example/f"/>'
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

    test('PRIV-004 subscriptions from before hosts were recorded are '
        'recorded once at start', () async {
      final show = await svc.subscribe('https://show.example/rss');
      hosts.entries.clear();
      await svc.syncHosts();
      expect(hosts.entries.single.$2, 'podcast:${show.id}');
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

    test('PRIV-004 an imported station list records the stations that '
        'were added', () async {
      final radio = RadioStations(MusicPrefs(db), hosts: hosts);
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
      await radio.dispose();
    });
  });
}

final class _Hosts implements FeedHostRegistry {
  final entries = <(String, String, String)>[];
  final removed = <String>[];

  @override
  Future<void> addFeedHost(
    Uri url, {
    required String owner,
    required String label,
  }) async => entries.add((url.toString(), owner, label));

  @override
  Future<void> removeFeedOwner(String owner) async => removed.add(owner);
}
