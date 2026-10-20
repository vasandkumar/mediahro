import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_home_widgets.dart';
import 'package:mediahro/platform/android/android_media.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: the now-playing home-screen widget on an Android device
/// (MUS-012). A debug-only hook reads the widget's stored state and taps its
/// buttons through the real receiver.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/session',
    StandardMessageCodec(),
  );
  Future<Object?> op(String name, [Object? arg]) => hook.send([name, arg]);
  Future<Map<Object?, Object?>> state() async =>
      (await op('widgetState'))! as Map<Object?, Object?>;

  testWidgets('MUS-012 Android bindings provide the home widget', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(homeWidgetsProvider), isA<AndroidHomeWidgets>());
  }, skip: !android);

  testWidgets('MUS-012 the widget shows the track and clears when stopped', (
    tester,
  ) async {
    final widgets = AndroidHomeWidgets();
    addTearDown(() => widgets.update(null, playing: false));
    await widgets.update(
      NowPlaying(
        title: 'So What',
        artist: 'Miles Davis',
        artwork: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
      ),
      playing: true,
    );
    final s = await state();
    expect(s['title'], 'So What');
    expect(s['artist'], 'Miles Davis');
    expect(s['playing'], isTrue);
    expect(s['hasArtwork'], isTrue);
    await widgets.update(null, playing: false);
    final cleared = await state();
    expect(cleared['title'], isNull);
    expect(cleared['hasArtwork'], isFalse);
  }, skip: !android);

  testWidgets('MUS-012 widget buttons reach the player as remote commands', (
    tester,
  ) async {
    final session = AndroidMediaSession();
    final got = <RemoteCommand>[];
    final sub = session.commands.listen(got.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final button in ['PLAY_PAUSE', 'NEXT', 'PREVIOUS']) {
      await op('widgetTap', button);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (got.length < 3 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(got.map((c) => c.runtimeType), [
      TogglePlayPauseCommand,
      NextCommand,
      PreviousCommand,
    ]);
  }, skip: !android);
}
