import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_system.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: open-with (CORE-003), share targets (SYS-004) and shortcuts
/// (SYS-003) on an Android device. A debug-only hook
/// (`mediahro.test/system`) sends real intents to MainActivity the way the
/// file manager, the share sheet and the launcher do.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/system',
    StandardMessageCodec(),
  );
  Future<Object?> op(String name, [String? arg]) => hook.send([name, arg]);

  late AndroidSystemIntegration system;
  late AndroidIntents intents;
  setUp(() {
    if (!android) return;
    system = AndroidSystemIntegration();
    intents = AndroidIntents();
  });

  testWidgets('CORE-003 Android bindings provide system integration', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(systemIntegrationProvider), isA<AndroidSystemIntegration>());
    expect(c.read(intentsProvider), isA<AndroidIntents>());
  }, skip: !android);

  testWidgets(
    'CORE-003 open with, SYS-004 shared files and links reach openRequests',
    (tester) async {
      final requests = <List<Uri>>[];
      final sub = system.openRequests.listen(requests.add);
      addTearDown(sub.cancel);
      Future<List<Uri>> next(Future<Object?> Function() send) async {
        final before = requests.length;
        await send();
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (requests.length == before) {
          if (DateTime.now().isAfter(deadline)) fail('no open request');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return requests.last;
      }

      final viewed = await next(() => op('view', 'c4a-open.mp4'));
      expect(viewed.single.scheme, 'content');
      expect(viewed.single.path, endsWith('c4a-open.mp4'));

      final link = await next(
        () => op('shareText', 'Watch https://example.com/live.m3u8 now'),
      );
      expect(link.single, Uri.parse('https://example.com/live.m3u8'));

      final many = await next(() => op('shareFiles', 'c4a-a.mkv,c4a-b.mkv'));
      expect(many.map((u) => u.pathSegments.last), ['c4a-a.mkv', 'c4a-b.mkv']);
    },
    skip: !android,
  );

  testWidgets('SYS-003 launcher shortcuts and App Actions reach incoming', (
    tester,
  ) async {
    final got = <AppIntent>[];
    final sub = intents.incoming.listen(got.add);
    addTearDown(sub.cancel);
    await op('shortcut', 'RESUME_LAST');
    await op('shortcut', 'OPEN_MODE');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (got.length < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(got.map((i) => i.kind), [
      AppIntentKind.resumeLast,
      AppIntentKind.openMode,
    ]);
    expect(got.last.argument, 'test-argument');
  }, skip: !android);

  testWidgets('SYS-003 published shortcuts appear in the launcher', (
    tester,
  ) async {
    await intents.publishShortcuts(const [
      AppShortcut(
        id: 'c4a-playlist',
        title: 'Road trip',
        intent: AppIntent(AppIntentKind.playPlaylist, argument: '42'),
      ),
      AppShortcut(
        id: 'c4a-music',
        title: 'Music',
        intent: AppIntent(AppIntentKind.openMode, argument: 'music'),
      ),
    ]);
    final ids = ((await op('dynamicShortcuts'))! as List<Object?>)
        .cast<String>();
    expect(ids, containsAll(['c4a-playlist', 'c4a-music']));
    await intents.publishShortcuts(const []);
  }, skip: !android);
}
