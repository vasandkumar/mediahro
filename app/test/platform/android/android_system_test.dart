import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_system.dart';
import 'package:mediahro/platform/android/gen/system_api.pigeon.dart' as pigeon;
import 'package:mediahro/platform/system_integration.dart';

/// The Dart half of lane C4a's open-with, share and shortcut handling.
final class _FakeIntents extends pigeon.IntentsHostApi {
  List<pigeon.AppShortcutMsg> published = const [];

  @override
  Future<void> publishShortcuts(List<pigeon.AppShortcutMsg> shortcuts) async =>
      published = shortcuts;
}

void main() {
  test(
    'CORE-003 open requests arrive as URIs; window members are inert',
    () async {
      final events = StreamController<pigeon.OpenRequestMsg>();
      final s = AndroidSystemIntegration(events: () => events.stream);
      final got = <List<Uri>>[];
      final sub = s.openRequests.listen(got.add);
      events.add(
        pigeon.OpenRequestMsg(uris: ['content://x/1', 'https://h/a.m3u8']),
      );
      await pumpEventQueue();
      await sub.cancel();
      expect(got.single, [
        Uri.parse('content://x/1'),
        Uri.parse('https://h/a.m3u8'),
      ]);
      expect(await s.windowFrame(), isNull);
      expect(await s.checkForUpdate(), isNull);
      await s.setAlwaysOnTop(enabled: true);
    },
  );

  test('SYS-003 shortcuts and intents map both ways', () async {
    final api = _FakeIntents();
    final events = StreamController<pigeon.AppIntentMsg>();
    final i = AndroidIntents(api: api, events: () => events.stream);
    await i.publishShortcuts(const [
      AppShortcut(
        id: 'p',
        title: 'Road trip',
        intent: AppIntent(AppIntentKind.playPlaylist, argument: '42'),
      ),
    ]);
    expect(api.published.single.kind, pigeon.AppIntentKindMsg.playPlaylist);
    expect(api.published.single.argument, '42');
    final got = <AppIntent>[];
    final sub = i.incoming.listen(got.add);
    events.add(
      pigeon.AppIntentMsg(
        kind: pigeon.AppIntentKindMsg.search,
        argument: 'blue',
      ),
    );
    await pumpEventQueue();
    await sub.cancel();
    expect(got.single.kind, AppIntentKind.search);
    expect(got.single.argument, 'blue');
  });
}
