import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/background_work_dispatcher.dart';
import 'package:mediahro/platform/platform_facades.dart';

final class _FakeWork implements BackgroundWorkFacade {
  final controller = StreamController<String>.broadcast();
  final completed = <(String, bool)>[];
  bool failComplete = false;

  @override
  Stream<String> get runs => controller.stream;

  @override
  Future<void> complete(String id, {required bool success}) async {
    completed.add((id, success));
    if (failComplete) throw StateError('job already gone');
  }

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

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late _FakeWork work;
  late BackgroundWorkDispatcher dispatcher;

  setUp(() {
    work = _FakeWork();
    dispatcher = BackgroundWorkDispatcher(
      work,
      handlerTimeout: const Duration(milliseconds: 200),
    )..start();
  });

  tearDown(() async {
    await dispatcher.dispose();
    await work.controller.close();
  });

  test('ADR-049 a run calls its handler and completes with success', () async {
    var calls = 0;
    dispatcher.register('pod.refresh', () async {
      calls++;
      return true;
    });
    work.controller.add('pod.refresh');
    await settle();
    expect(calls, 1);
    expect(work.completed, [('pod.refresh', true)]);
  });

  test(
    'ADR-049 a handler that reports failure completes with failure',
    () async {
      dispatcher.register('pod.refresh', () async => false);
      work.controller.add('pod.refresh');
      await settle();
      expect(work.completed, [('pod.refresh', false)]);
    },
  );

  test('ADR-049 a handler that throws is a failure, not a crash', () async {
    dispatcher.register('pod.refresh', () async => throw StateError('boom'));
    work.controller.add('pod.refresh');
    await settle();
    expect(work.completed, [('pod.refresh', false)]);
  });

  test(
    'ADR-049 an unknown id completes as success so it is not retried',
    () async {
      work.controller.add('gone.feature');
      await settle();
      expect(work.completed, [('gone.feature', true)]);
    },
  );

  test('ADR-049 each id goes to its own handler', () async {
    final seen = <String>[];
    dispatcher
      ..register('a', () async {
        seen.add('a');
        return true;
      })
      ..register('b', () async {
        seen.add('b');
        return false;
      });
    work.controller
      ..add('b')
      ..add('a');
    await settle();
    expect(seen, ['b', 'a']);
    expect(work.completed, [('b', false), ('a', true)]);
  });

  test(
    'ADR-049 registering again replaces the handler; unregister removes it',
    () async {
      final seen = <String>[];
      dispatcher
        ..register('a', () async {
          seen.add('old');
          return true;
        })
        ..register('a', () async {
          seen.add('new');
          return true;
        });
      work.controller.add('a');
      await settle();
      expect(seen, ['new']);
      dispatcher.unregister('a');
      work.controller.add('a');
      await settle();
      expect(seen, ['new']);
      expect(work.completed.last, ('a', true));
    },
  );

  test(
    'ADR-049 a handler that never finishes is a failure after the timeout',
    () async {
      dispatcher.register('slow', () => Completer<bool>().future);
      work.controller.add('slow');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(work.completed, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(work.completed, [('slow', false)]);
    },
  );

  test('ADR-049 a complete that fails does not stop later runs', () async {
    work.failComplete = true;
    dispatcher.register('a', () async => true);
    work.controller.add('a');
    await settle();
    work.failComplete = false;
    work.controller.add('a');
    await settle();
    expect(work.completed.length, 2);
  });

  test('ADR-049 start twice listens once; dispose stops listening', () async {
    var calls = 0;
    dispatcher
      ..start()
      ..register('a', () async {
        calls++;
        return true;
      });
    work.controller.add('a');
    await settle();
    expect(calls, 1);
    await dispatcher.dispose();
    work.controller.add('a');
    await settle();
    expect(calls, 1);
  });

  test('ADR-049 the provider listens as soon as it is read', () async {
    final fake = _FakeWork();
    final container = ProviderContainer(
      overrides: [backgroundWorkProvider.overrideWithValue(fake)],
    );
    addTearDown(() async {
      container.dispose();
      await fake.controller.close();
    });
    final read = container.read(backgroundWorkDispatcherProvider);
    expect(fake.controller.hasListener, isTrue);
    read.register('a', () async => true);
    fake.controller.add('a');
    await settle();
    expect(fake.completed, [('a', true)]);
    container.dispose();
    expect(fake.controller.hasListener, isFalse);
  });

  test('ADR-049 without a native facade nothing runs and nothing breaks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(backgroundWorkDispatcherProvider), isNotNull);
  });
}
