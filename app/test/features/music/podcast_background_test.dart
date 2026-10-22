import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/podcasts/podcast_background.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro/platform/background_work.dart';

import 'podcast_test_support.dart';

/// POD-002 while the app is closed (ADR-049): scheduled only with a
/// subscription, on an unmetered connection, and a wake-up checks the feeds.
void main() {
  late LibraryDatabase db;
  late FakeNet net;
  late PodcastService service;
  late _Work work;
  late PodcastBackgroundRefresh refresh;
  var now = DateTime.utc(2026, 10, 22, 12);

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Parsing a feed runs on an isolate: wait for the run to report.
  Future<void> reported(int runs) async {
    for (var i = 0; i < 500 && work.completed.length < runs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 22, 12);
    db = LibraryDatabase.memory();
    net = FakeNet()..serve('https://show.example/rss', podcastRss);
    service = PodcastService(
      store: PodcastStore(MusicPrefs(db)),
      http: net.http,
      downloads: FakeDownloads(),
      clock: () => now,
    );
    work = _Work();
    refresh = PodcastBackgroundRefresh(work: work, service: service);
  });
  tearDown(() async {
    await refresh.dispose();
    await service.dispose();
    await db.close();
  });

  test('POD-002 where the platform cannot wake the app, nothing is '
      'scheduled', () async {
    work.supported = false;
    await service.subscribe('https://show.example/rss');
    await refresh.start();
    await settle();
    expect(work.scheduled, isEmpty);
  });

  test('POD-002 nothing is scheduled until there is a subscription; it is '
      'cancelled with the last one', () async {
    await refresh.start();
    await settle();
    expect(work.scheduled, isEmpty);
    final show = await service.subscribe('https://show.example/rss');
    await settle();
    expect(work.scheduled.single.id, PodcastBackgroundRefresh.taskId);
    expect(work.scheduled.single.interval, const Duration(hours: 3));
    expect(work.scheduled.single.unmeteredOnly, isTrue);
    expect(work.scheduled.single.requiresNetwork, isTrue);
    expect(work.scheduled.single.requiresCharging, isFalse);
    await service.unsubscribe(show.id);
    await settle();
    expect(work.cancelled, [PodcastBackgroundRefresh.taskId]);
    expect(work.scheduled, hasLength(1));
  });

  test('POD-002 a wake-up checks the feeds and reports the outcome to the '
      'OS', () async {
    await service.subscribe('https://show.example/rss');
    await refresh.start();
    await settle();
    final before = net.requests.length;
    now = now.add(const Duration(hours: 4));
    work.wake('somebody.else');
    await settle();
    expect(net.requests.length, before, reason: 'not our task');
    work.wake(PodcastBackgroundRefresh.taskId);
    await reported(1);
    expect(net.requests.length, greaterThan(before));
    expect(work.completed, [(PodcastBackgroundRefresh.taskId, true)]);

    // Every feed failing is a failed run: the OS may retry later.
    net.serve('https://show.example/rss', '', status: 500);
    now = now.add(const Duration(hours: 4));
    work.wake(PodcastBackgroundRefresh.taskId);
    await reported(2);
    expect(work.completed.last, (PodcastBackgroundRefresh.taskId, false));
  });
}

final class _Work implements BackgroundWorkFacade {
  bool supported = true;
  final scheduled =
      <
        ({
          String id,
          Duration interval,
          bool requiresNetwork,
          bool unmeteredOnly,
          bool requiresCharging,
        })
      >[];
  final cancelled = <String>[];
  final completed = <(String, bool)>[];
  final _runs = StreamController<String>.broadcast();

  void wake(String id) => _runs.add(id);

  @override
  Future<void> schedulePeriodic(
    String id,
    Duration interval, {
    bool requiresNetwork = true,
    bool unmeteredOnly = false,
    bool requiresCharging = false,
  }) async => scheduled.add((
    id: id,
    interval: interval,
    requiresNetwork: requiresNetwork,
    unmeteredOnly: unmeteredOnly,
    requiresCharging: requiresCharging,
  ));

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  @override
  Stream<String> get runs => _runs.stream;

  @override
  Future<void> complete(String id, {required bool success}) async =>
      completed.add((id, success));

  @override
  Future<bool> get available async => supported;
}
