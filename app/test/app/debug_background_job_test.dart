import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/background_work_dispatcher.dart';
import 'package:mediahro/app/debug/debug_background_job.dart';
import 'package:mediahro/platform/platform_facades.dart';

final class _Work implements BackgroundWorkFacade {
  final controller = StreamController<String>.broadcast();
  final completed = <(String, bool)>[];

  @override
  Stream<String> get runs => controller.stream;

  @override
  Future<void> complete(String id, {required bool success}) async =>
      completed.add((id, success));

  @override
  Future<void> schedulePeriodic(
    String id,
    Duration interval, {
    bool requiresNetwork = true,
    bool unmeteredOnly = false,
    bool requiresCharging = false,
  }) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<bool> get available async => true;
}

void main() {
  test('ADR-049 the debug job logs that it ran and succeeds', () async {
    final work = _Work();
    final logs = <String>[];
    final dispatcher = BackgroundWorkDispatcher(work)..start();
    registerDebugBackgroundJob(dispatcher, log: logs.add);
    addTearDown(() async {
      await dispatcher.dispose();
      await work.controller.close();
    });

    work.controller.add(debugLeaveJobId);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(logs, ['bg: ran debug.leave']);
    expect(work.completed, [(debugLeaveJobId, true)]);
  });

  test('ADR-049 the debug job id is the one the receiver schedules', () {
    // DebugJobReceiver.DEFAULT_ID in src/debug.
    expect(debugLeaveJobId, 'debug.leave');
  });

  test('ADR-049 other jobs are not touched by the debug handler', () async {
    final work = _Work();
    final logs = <String>[];
    final dispatcher = BackgroundWorkDispatcher(work)..start();
    registerDebugBackgroundJob(dispatcher, log: logs.add);
    addTearDown(() async {
      await dispatcher.dispose();
      await work.controller.close();
    });

    work.controller.add('pod.refresh');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(logs, isEmpty);
    // An unknown id still completes as a success, so it is not retried.
    expect(work.completed, [('pod.refresh', true)]);
  });
}
