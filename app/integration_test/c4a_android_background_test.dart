import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_background_work.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: scheduled background work on an Android device (ADR-049). A
/// periodic WorkManager job runs every 15 minutes at best, so the schedule is
/// checked through what WorkManager holds (debug hook `mediahro.test/background`)
/// and the run path by starting one run of the same worker at once.
///
/// The cold path (the app closed, the OS starts a process and the engine
/// without a screen) cannot be driven from inside the app; it is the manual
/// check at the end of the PR: schedule, swipe the app away, then
/// `adb shell cmd jobscheduler run -f com.mediahro.mediahro <job id>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;
  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/background',
    StandardMessageCodec(),
  );
  const id = 'c4a.test.refresh';

  Future<Map<Object?, Object?>?> job() async =>
      await hook.send(<Object?>['job', id]) as Map<Object?, Object?>?;
  Future<String> startRun() async =>
      (await hook.send(<Object?>['run', id]))! as String;
  Future<List<Object?>?> runState(String work) async =>
      await hook.send(<Object?>['state', work]) as List<Object?>?;
  Future<void> waitForState(String work, String want) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      if ((await runState(work))?.first == want) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect((await runState(work))?.first, want);
  }

  tearDown(() async {
    if (android) await AndroidBackgroundWork().cancel(id);
  });

  testWidgets('ADR-049 Android bindings provide the background work facade', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(backgroundWorkProvider), isA<AndroidBackgroundWork>());
    expect(await c.read(backgroundWorkProvider).available, isTrue);
  }, skip: !android);

  testWidgets('ADR-049 a schedule is a WorkManager job with the constraints', (
    tester,
  ) async {
    final work = AndroidBackgroundWork();
    expect(await job(), isNull);
    await work.schedulePeriodic(id, const Duration(hours: 6));
    // Enqueueing is asynchronous.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    var held = await job();
    expect(held, isNotNull);
    expect(held!['intervalMs'], const Duration(hours: 6).inMilliseconds);
    expect(held['network'], 'CONNECTED');
    expect(held['charging'], isFalse);
    expect(held['state'], 'ENQUEUED');

    // Scheduling the same id again replaces the job rather than adding one.
    await work.schedulePeriodic(
      id,
      const Duration(hours: 12),
      unmeteredOnly: true,
      requiresCharging: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    held = await job();
    expect(held!['intervalMs'], const Duration(hours: 12).inMilliseconds);
    expect(held['network'], 'UNMETERED');
    expect(held['charging'], isTrue);

    // No network needed.
    await work.schedulePeriodic(
      id,
      const Duration(hours: 1),
      requiresNetwork: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect((await job())!['network'], 'NOT_REQUIRED');
  }, skip: !android);

  testWidgets('ADR-049 an interval under 15 minutes is raised to 15 minutes', (
    tester,
  ) async {
    await AndroidBackgroundWork().schedulePeriodic(
      id,
      const Duration(minutes: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(
      (await job())!['intervalMs'],
      const Duration(minutes: 15).inMilliseconds,
    );
  }, skip: !android);

  testWidgets('ADR-049 cancel removes the job and is harmless twice', (
    tester,
  ) async {
    final work = AndroidBackgroundWork();
    await work.schedulePeriodic(id, const Duration(hours: 1));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await job(), isNotNull);
    await work.cancel(id);
    await work.cancel(id);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await job(), isNull);
  }, skip: !android);

  testWidgets('ADR-049 a run delivers its id and success finishes the work', (
    tester,
  ) async {
    final work = AndroidBackgroundWork();
    final ids = StreamController<String>();
    final sub = work.runs.listen(ids.add);
    addTearDown(sub.cancel);
    final run = await startRun();
    final got = await ids.stream.first.timeout(const Duration(seconds: 20));
    expect(got, id);
    await work.complete(got, success: true);
    await waitForState(run, 'SUCCEEDED');
  }, skip: !android);

  testWidgets('ADR-049 a failed run is retried later', (tester) async {
    final work = AndroidBackgroundWork();
    final ids = StreamController<String>();
    final sub = work.runs.listen(ids.add);
    addTearDown(sub.cancel);
    final run = await startRun();
    final got = await ids.stream.first.timeout(const Duration(seconds: 20));
    await work.complete(got, success: false);
    // Result.retry puts the work back in the queue with its attempt counted.
    final end = DateTime.now().add(const Duration(seconds: 20));
    List<Object?>? state;
    while (DateTime.now().isBefore(end)) {
      state = await runState(run);
      if (state?.first == 'ENQUEUED' && (state![1]! as int) >= 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(state?.first, 'ENQUEUED');
    expect(state![1]! as int, greaterThanOrEqualTo(1));
    await hook.send(<Object?>['stop', run]);
  }, skip: !android);
}
