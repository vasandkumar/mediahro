import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/incoming/incoming_router.dart'
    show appRouterProvider;
import 'package:mediahro/features/video/player/play_request.dart';
    show videoMemoryProvider;
import 'package:mediahro/features/video/player/video_player_screen.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../../../integration_test/support/c1_platform.dart';
import '../../../integration_test/support/c1_player.dart';

/// VID-067 (hand check, store profile APK): after picture-in-picture and
/// Back, opening a file again did nothing.
void main() {
  PlayRequest second() => PlayRequest(
    source: UriSource(Uri.parse('file:///v/second.mkv')),
    title: 'Second',
    memoryKey: 'second',
  );

  /// The app's router, also while only a bare video is on screen.
  GoRouter routerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MediahroApp)))
          .read(appRouterProvider)!;

  playerTest('VID-067 a video opens again after PiP and Back', (tester) async {
    final pip = FakePip();
    final (engine, _) = await pumpPlayer(
      tester,
      overrides: [pipProvider.overrideWithValue(pip)],
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(iconButton('Picture in picture'));
    await tester.pumpAndSettle();
    expect(iconButton('Back'), findsNothing);
    // The user taps the window to come back, then presses Back.
    pip.setActive(active: false);
    await tester.pumpAndSettle();
    await tester.tap(iconButton('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayerScreen), findsNothing);

    final opens = engine.calls.where((c) => c == 'open').length;
    unawaited(routerOf(tester).push(VideoRoutes.play, extra: second()));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(engine.calls.where((c) => c == 'open').length, opens + 1);
    expect(find.text('Second'), findsWidgets);
  });

  playerTest('VID-067 Back while the PiP window is still reported open', (
    tester,
  ) async {
    // The platform may report the end of picture-in-picture late (or never,
    // when the activity is left from the window): the next player must not
    // inherit "in PiP" and show only a bare video.
    final pip = FakePip();
    final (engine, _) = await pumpPlayer(
      tester,
      overrides: [pipProvider.overrideWithValue(pip)],
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(iconButton('Picture in picture'));
    await tester.pumpAndSettle();
    routerOf(tester).pop();
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayerScreen), findsNothing);

    unawaited(routerOf(tester).push(VideoRoutes.play, extra: second()));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    // Not stuck in the bare PiP layout: the controls are there.
    expect(iconButton('Back'), findsOneWidget);
    expect(engine.calls, contains('open'));
  });

  playerTest('VID-067 a slow stop of the last video cannot cancel the next', (
    tester,
  ) async {
    // The engine is shared and its stop is asynchronous. A stop that lands
    // after the next open began made that open give up quietly: no picture,
    // no error. The next player now opens only after the stop.
    final (engine, _) = await pumpPlayer(tester);
    final gate = Completer<void>();
    engine.stopGate = gate.future;
    await tester.tap(iconButton('Back'));
    await tester.pumpAndSettle();
    unawaited(routerOf(tester).push(VideoRoutes.play, extra: second()));
    await tester.pump(const Duration(milliseconds: 200));

    final firstOpen = engine.calls.indexOf('open');
    expect(
      engine.calls.where((c) => c == 'open'),
      hasLength(1),
      reason: 'waits for the stop',
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    final calls = engine.calls;
    expect(calls.where((c) => c == 'open'), hasLength(2));
    expect(calls.lastIndexOf('open'), greaterThan(calls.lastIndexOf('stop')));
    expect(firstOpen, isNonNegative);
  });

  playerTest('VID-067 a player that cannot start says so instead of a black '
      'screen', (tester) async {
    await pumpPlayer(
      tester,
      overrides: [
        videoProgressProvider.overrideWith((ref) => throw StateError('x')),
      ],
    );

    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(find.textContaining('went wrong'), findsOneWidget);
    expect(find.text('Choose another'), findsOneWidget);
  });
}
