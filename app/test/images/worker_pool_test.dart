import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';

// Top-level so it can cross the isolate boundary.
WorkerHandler echoFactory() => (request) async {
  final r = request! as List<Object?>;
  switch (r[0]) {
    case 'echo':
      return r[1];
    case 'sleep':
      await Future<void>.delayed(Duration(milliseconds: r[1]! as int));
      return r[2];
    case 'isolate':
      return Isolate.current.debugName;
    case 'throw':
      throw StateError('boom');
  }
  return null;
};

WorkerHandler failingFactory() => throw StateError('no native library');

void main() {
  test(
    'IMG-003 jobs run on a worker isolate and return their result',
    () async {
      final pool = IsolateWorkerPool(size: 1, factory: echoFactory);
      addTearDown(pool.dispose);
      expect(await pool.submit<Object?>(['echo', 42]), 42);
      expect(
        await pool.submit<Object?>(['isolate']),
        isNot(Isolate.current.debugName),
      );
    },
  );

  test(
    'IMG-003 the highest priority runs first, oldest first within one',
    () async {
      final pool = IsolateWorkerPool(size: 1, factory: echoFactory);
      addTearDown(pool.dispose);
      final order = <String>[];
      // The first job occupies the single worker while the rest queue up.
      final busy = pool.submit<Object?>(['sleep', 80, 'busy']);
      Future<void> job(String name, int priority) => pool
          .submit<Object?>(['echo', name], priority: priority)
          .then((v) => order.add(v! as String));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await Future.wait([
        job('prefetch-1', 0),
        job('visible-1', 2),
        job('nearby-1', 1),
        job('visible-2', 2),
        job('prefetch-2', 0),
        busy,
      ]);
      expect(order, [
        'visible-1',
        'visible-2',
        'nearby-1',
        'prefetch-1',
        'prefetch-2',
      ]);
    },
  );

  test('IMG-003 cancelBelow drops queued low-priority jobs only', () async {
    final pool = IsolateWorkerPool(size: 1, factory: echoFactory);
    addTearDown(pool.dispose);
    final busy = pool.submit<Object?>(['sleep', 80, 'busy'], priority: 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final low = pool.submit<Object?>(['echo', 'low']);
    final nearby = pool.submit<Object?>(['echo', 'nearby'], priority: 1);
    final high = pool.submit<Object?>(['echo', 'high'], priority: 2);
    final lowResult = expectLater(low, throwsA(isA<JobCancelled>()));
    pool.cancelBelow(1);
    await lowResult;
    expect(await nearby, 'nearby');
    expect(await high, 'high');
    expect(await busy, 'busy', reason: 'the running job always finishes');
  });

  test('IMG-003 reprioritise moves queued jobs of a screen ahead', () async {
    final pool = IsolateWorkerPool(size: 1, factory: echoFactory);
    addTearDown(pool.dispose);
    final order = <String>[];
    final busy = pool.submit<Object?>(['sleep', 80, 'busy']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    Future<void> job(String name, Object group) => pool
        .submit<Object?>(['echo', name], group: group)
        .then((v) => order.add(v! as String));
    final all = Future.wait([
      job('a1', 'a'),
      job('b1', 'b'),
      job('a2', 'a'),
      busy,
    ]);
    pool.reprioritise('b', 5);
    await all;
    expect(order.first, 'b1');
  });

  test('IMG-003 workers run in parallel up to the pool size', () async {
    final pool = IsolateWorkerPool(size: 3, factory: echoFactory);
    addTearDown(pool.dispose);
    final sw = Stopwatch()..start();
    await Future.wait([
      for (var i = 0; i < 3; i++) pool.submit<Object?>(['sleep', 300, i]),
    ]);
    // Serial execution would take at least 900 ms.
    expect(sw.elapsedMilliseconds, lessThan(850));
    expect(pool.queued, 0);
  });

  test('IMG-003 a handler error fails only its job', () async {
    final pool = IsolateWorkerPool(size: 1, factory: echoFactory);
    addTearDown(pool.dispose);
    await expectLater(
      pool.submit<Object?>(['throw']),
      throwsA(isA<WorkerException>()),
    );
    expect(await pool.submit<Object?>(['echo', 'still alive']), 'still alive');
  });

  test(
    'IMG-003 a worker that cannot start fails the queue instead of hanging',
    () async {
      final pool = IsolateWorkerPool(size: 2, factory: failingFactory);
      addTearDown(pool.dispose);
      await expectLater(
        pool.submit<Object?>(['echo', 1]).timeout(const Duration(seconds: 10)),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('IMG-003 dispose fails queued jobs', () async {
    final pool = IsolateWorkerPool(size: 1, factory: echoFactory);
    final busy = pool.submit<Object?>(['sleep', 200, 'x']);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final waiting = pool.submit<Object?>(['echo', 1]);
    final w = expectLater(waiting, throwsA(isA<JobCancelled>()));
    final b = expectLater(busy, throwsA(isA<JobCancelled>()));
    await pool.dispose();
    await w;
    await b;
    await expectLater(pool.submit<Object?>(['echo', 1]), throwsStateError);
  });
}
