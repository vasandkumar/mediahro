import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_car.dart';
import 'package:mediahro/platform/android/android_media.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: MediaBrowseFacade (Android Auto, MUS-013) and AlarmFacade
/// (MUS-011) on an Android device. A debug-only Media3 MediaBrowser
/// (`mediahro.test/car`) browses, searches and plays the way Android Auto
/// and the Assistant do.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/car',
    StandardMessageCodec(),
  );
  Future<Object?> op(String name, [String? arg]) => hook.send([name, arg]);

  tearDown(() async {
    if (android) await op('release');
  });

  testWidgets('MUS-013 Android bindings provide car browsing and alarms', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(mediaBrowseProvider), isA<AndroidMediaBrowse>());
    expect(c.read(alarmProvider), isA<AndroidAlarms>());
  }, skip: !android);

  testWidgets(
    'MUS-013 the car browses, searches and plays through the provider',
    (tester) async {
      // The library session lives in the media service; activate it first.
      final session = AndroidMediaSession();
      await session.activate(MediaSessionKind.music);
      addTearDown(session.deactivate);
      final provider = _Provider();
      await AndroidMediaBrowse().register(provider);

      final root = (await op('root'))! as Map<Object?, Object?>;
      expect(root['id'], MediaBrowseNode.rootId);
      expect(root['browsable'], isTrue);

      final top = ((await op('children', 'root'))! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(top.map((n) => n['title']), ['Albums', 'Kind of Blue']);
      expect(top.first['browsable'], isTrue);
      expect(top.last['playable'], isTrue);
      expect(top.last['subtitle'], 'Miles Davis');

      final found = ((await op('search', 'blue'))! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(found.single['id'], 'album:kob');
      expect(provider.searches, ['blue']);

      await op('play', 'album:kob');
      await _eventually(() => provider.played.contains('album:kob'));

      // "Play blue on Mediahro": a voice query becomes the first playable hit.
      provider.played.clear();
      await op('voice', 'blue');
      await _eventually(() => provider.played.contains('album:kob'));
    },
    skip: !android,
  );

  testWidgets('MUS-011 an alarm fires into the running app', (tester) async {
    if (await op('canExactAlarms') != true) {
      return markTestSkipped(
        'Alarms & reminders not granted; allow it first: '
        'adb shell appops set com.mediahro.app SCHEDULE_EXACT_ALARM allow',
      );
    }
    final alarms = AndroidAlarms();
    expect(await alarms.isSupported(), isTrue);
    final fired = <String>[];
    final sub = alarms.fired.listen(fired.add);
    addTearDown(sub.cancel);

    await alarms.schedule(
      ScheduledAlarm(
        id: 'c4a-cancelled',
        at: DateTime.now().add(const Duration(seconds: 4)),
        label: 'Cancelled',
      ),
    );
    await alarms.cancel('c4a-cancelled');
    await alarms.schedule(
      ScheduledAlarm(
        id: 'c4a-test',
        at: DateTime.now().add(const Duration(seconds: 5)),
        label: 'Wake up',
      ),
    );
    await _eventually(
      () => fired.contains('c4a-test'),
      timeout: const Duration(seconds: 30),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(fired, isNot(contains('c4a-cancelled')));
  }, skip: !android);

  testWidgets('MUS-011 opening the app from an alarm delivers its id', (
    tester,
  ) async {
    final alarms = AndroidAlarms();
    final fired = Completer<String>();
    final sub = alarms.fired.listen((id) {
      if (!fired.isCompleted) fired.complete(id);
    });
    addTearDown(sub.cancel);
    await op('openFromAlarm', 'c4a-launch');
    expect(
      await fired.future.timeout(const Duration(seconds: 10)),
      'c4a-launch',
    );
  }, skip: !android);
}

Future<void> _eventually(
  bool Function() check, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

final class _Provider implements MediaBrowseProvider {
  final searches = <String>[];
  final played = <String>[];

  static const _albums = MediaBrowseNode(
    id: 'albums',
    title: 'Albums',
    playable: false,
    browsable: true,
  );
  static const _kob = MediaBrowseNode(
    id: 'album:kob',
    title: 'Kind of Blue',
    subtitle: 'Miles Davis',
    playable: true,
    browsable: true,
  );

  @override
  Future<List<MediaBrowseNode>> children(String nodeId, {int page = 0}) async =>
      nodeId == MediaBrowseNode.rootId && page == 0 ? [_albums, _kob] : [];

  @override
  Future<List<MediaBrowseNode>> search(String query) async {
    searches.add(query);
    return query.contains('blue') ? [_kob] : [];
  }

  @override
  Future<void> play(String nodeId) async => played.add(nodeId);
}
