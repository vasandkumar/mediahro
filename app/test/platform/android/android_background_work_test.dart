import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_background_work.dart';
import 'package:mediahro/platform/android/gen/background_api.pigeon.dart';

/// The Dart half of lane C4a's scheduled background work (ADR-049).
final class _FakeApi extends BackgroundWorkHostApi {
  final calls = <List<Object?>>[];
  bool supported = true;

  @override
  Future<void> schedulePeriodic(
    String id,
    int intervalMs,
    bool requiresNetwork,
    bool unmeteredOnly,
    bool requiresCharging,
  ) async => calls.add([
    'schedule',
    id,
    intervalMs,
    requiresNetwork,
    unmeteredOnly,
    requiresCharging,
  ]);

  @override
  Future<void> cancel(String id) async => calls.add(['cancel', id]);

  @override
  Future<void> complete(String id, bool success) async =>
      calls.add(['complete', id, success]);

  @override
  Future<bool> available() async => supported;
}

void main() {
  late _FakeApi api;
  late StreamController<String> events;
  late AndroidBackgroundWork work;

  setUp(() {
    api = _FakeApi();
    events = StreamController<String>.broadcast();
    work = AndroidBackgroundWork(api: api, events: () => events.stream);
  });

  tearDown(() => unawaited(events.close()));

  test('ADR-049 a schedule passes the interval and the constraints', () async {
    await work.schedulePeriodic(
      'pod.refresh',
      const Duration(hours: 6),
      unmeteredOnly: true,
      requiresCharging: true,
    );
    expect(api.calls, [
      ['schedule', 'pod.refresh', 6 * 60 * 60 * 1000, true, true, true],
    ]);
  });

  test('ADR-049 the defaults need a network, any kind, on battery', () async {
    await work.schedulePeriodic('pod.refresh', const Duration(minutes: 30));
    expect(api.calls.single, [
      'schedule',
      'pod.refresh',
      30 * 60 * 1000,
      true,
      false,
      false,
    ]);
  });

  test('ADR-049 an empty id is refused before it reaches the OS', () {
    expect(
      () => work.schedulePeriodic(' ', const Duration(hours: 1)),
      throwsArgumentError,
    );
    expect(api.calls, isEmpty);
  });

  test('ADR-049 cancel and complete are passed through', () async {
    await work.cancel('pod.refresh');
    await work.complete('pod.refresh', success: true);
    await work.complete('pod.refresh', success: false);
    expect(api.calls, [
      ['cancel', 'pod.refresh'],
      ['complete', 'pod.refresh', true],
      ['complete', 'pod.refresh', false],
    ]);
  });

  test('ADR-049 runs delivers the id of each job the OS started', () async {
    final seen = <String>[];
    final sub = work.runs.listen(seen.add);
    events
      ..add('pod.refresh')
      ..add('other');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, ['pod.refresh', 'other']);
  });

  test('ADR-049 availability comes from the host', () async {
    expect(await work.available, isTrue);
    api.supported = false;
    expect(await work.available, isFalse);
  });
}
