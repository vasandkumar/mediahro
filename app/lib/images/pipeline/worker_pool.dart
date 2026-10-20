import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

/// Runs inside a worker isolate: handles one request and returns the reply.
/// Both must be sendable (typed data, records, plain classes).
typedef WorkerHandler = FutureOr<Object?> Function(Object? request);

/// Builds the handler inside the worker isolate. Must be a top-level or
/// static function so it can cross the isolate boundary; it is where a
/// worker loads its native libraries.
typedef WorkerHandlerFactory = WorkerHandler Function();

/// Thrown by a queued job that was dropped before it started.
final class JobCancelled implements Exception {
  const JobCancelled();

  @override
  String toString() => 'JobCancelled';
}

/// A handler threw inside a worker; [remoteStack] is the worker's trace.
final class WorkerException implements Exception {
  const WorkerException(this.message, this.remoteStack);

  final String message;
  final String remoteStack;

  @override
  String toString() => 'WorkerException: $message';
}

/// What a caller can say about a queued job so it can be dropped later.
final class JobHandle {
  JobHandle._(this.priority, this.group);

  /// Larger runs first.
  int priority;

  /// Opaque grouping key (a gallery screen, an item).
  final Object? group;
}

final class _Job {
  _Job(this.id, this.request, this.handle, this.seq);

  final int id;
  final Object? request;
  final JobHandle handle;
  final int seq;
  final Completer<Object?> completer = Completer<Object?>();
}

final class _Worker {
  _Worker(this.isolate, this.send, this.receive);

  final Isolate isolate;
  final SendPort send;
  final ReceivePort receive;
  _Job? current;
}

/// A pool of long-lived isolates with a priority queue in front
/// (docs/05 §7: "scan and thumbnail queues are priority queues keyed to the
/// visible viewport"). Jobs run highest priority first, oldest first within
/// a priority; queued jobs can be re-prioritised or dropped as the viewport
/// moves; running jobs always finish.
final class IsolateWorkerPool {
  IsolateWorkerPool({required this.size, required this.factory})
    : assert(size > 0, 'a pool needs at least one worker');

  final int size;
  final WorkerHandlerFactory factory;

  final List<_Worker> _workers = [];
  final List<_Worker> _idle = [];
  final SplayTreeMap<(int, int), _Job> _queue = SplayTreeMap(
    (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2),
  );
  int _seq = 0;
  int _spawning = 0;
  bool _disposed = false;

  /// Jobs waiting for a worker.
  int get queued => _queue.length;

  /// Jobs a worker is running.
  int get running => _workers.where((w) => w.current != null).length;

  /// Queues [request]; the result completes when a worker has handled it.
  /// Returns the handle through [onQueued] so callers can re-prioritise.
  Future<T> submit<T>(
    Object? request, {
    int priority = 0,
    Object? group,
    void Function(JobHandle handle)? onQueued,
  }) {
    if (_disposed) return Future.error(StateError('pool disposed'));
    final handle = JobHandle._(priority, group);
    final job = _Job(++_seq, request, handle, _seq);
    _queue[(priority, job.seq)] = job;
    onQueued?.call(handle);
    _pump();
    return job.completer.future.then((v) => v as T);
  }

  /// Changes the priority of every queued job in [group].
  void reprioritise(Object? group, int priority) {
    final moved = [
      for (final e in _queue.entries)
        if (e.value.handle.group == group) e,
    ];
    for (final e in moved) {
      _queue.remove(e.key);
      e.value.handle.priority = priority;
      _queue[(priority, e.value.seq)] = e.value;
    }
  }

  /// Drops queued jobs whose priority is below [priority]; their futures
  /// fail with [JobCancelled].
  void cancelBelow(int priority) => cancelWhere((h) => h.priority < priority);

  /// Drops queued jobs for which [test] is true.
  void cancelWhere(bool Function(JobHandle handle) test) {
    final drop = [
      for (final e in _queue.entries)
        if (test(e.value.handle)) e,
    ];
    for (final e in drop) {
      _queue.remove(e.key);
      e.value.completer.completeError(const JobCancelled());
    }
  }

  void _pump() {
    while (_queue.isNotEmpty && _idle.isNotEmpty) {
      final w = _idle.removeLast();
      final key = _queue.firstKey()!;
      final job = _queue.remove(key)!;
      w.current = job;
      w.send.send((job.id, job.request));
    }
    if (_queue.isNotEmpty &&
        _idle.isEmpty &&
        _workers.length + _spawning < size) {
      _spawning++;
      unawaited(_spawn());
    }
  }

  Future<void> _spawn() async {
    final ready = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(_workerMain, (ready.sendPort, factory));
    } on Object {
      ready.close();
      _spawning--;
      _failQueued();
      return;
    }
    final results = ReceivePort();
    var worker = _Worker(isolate, ready.sendPort, results);
    final sendPortCompleter = Completer<SendPort>();
    ready.listen((m) {
      if (m is SendPort && !sendPortCompleter.isCompleted) {
        sendPortCompleter.complete(m);
      } else if (m is _Failed && !sendPortCompleter.isCompleted) {
        sendPortCompleter.completeError(m);
      }
    });
    final SendPort port;
    try {
      port = await sendPortCompleter.future;
    } on Object {
      ready.close();
      results.close();
      isolate.kill(priority: Isolate.immediate);
      _spawning--;
      _failQueued();
      return;
    }
    ready.close();
    worker = _Worker(isolate, port, results);
    port.send(results.sendPort);
    results.listen((m) => _onReply(worker, m));
    _spawning--;
    _workers.add(worker);
    if (_disposed) {
      _kill(worker);
      return;
    }
    _idle.add(worker);
    _pump();
  }

  void _failQueued() {
    // Nothing can run: fail what waits, so callers fall back instead of hang.
    if (_workers.isNotEmpty) return;
    final jobs = _queue.values.toList();
    _queue.clear();
    for (final j in jobs) {
      j.completer.completeError(StateError('image worker could not start'));
    }
  }

  void _onReply(_Worker w, Object? m) {
    final job = w.current;
    w.current = null;
    if (m is _Reply && job != null && m.id == job.id) {
      if (m.error != null) {
        job.completer.completeError(WorkerException(m.error!, m.stack ?? ''));
      } else {
        job.completer.complete(m.value);
      }
    }
    if (!_disposed) {
      _idle.add(w);
      _pump();
    } else {
      _kill(w);
    }
  }

  void _kill(_Worker w) {
    w.receive.close();
    w.isolate.kill(priority: Isolate.immediate);
  }

  /// Stops the workers; queued jobs fail, running ones are abandoned.
  Future<void> dispose() async {
    _disposed = true;
    cancelWhere((_) => true);
    for (final w in _workers) {
      w.current?.completer.completeError(const JobCancelled());
      _kill(w);
    }
    _workers.clear();
    _idle.clear();
  }
}

final class _Reply {
  const _Reply(this.id, this.value, this.error, this.stack);

  final int id;
  final Object? value;
  final String? error;
  final String? stack;
}

final class _Failed {
  const _Failed(this.message);

  final String message;
}

Future<void> _workerMain((SendPort, WorkerHandlerFactory) args) async {
  final (ready, factory) = args;
  final commands = ReceivePort();
  WorkerHandler handler;
  try {
    handler = factory();
  } on Object catch (e) {
    ready.send(_Failed('$e'));
    return;
  }
  ready.send(commands.sendPort);
  SendPort? results;
  await for (final Object? m in commands) {
    if (m is SendPort) {
      results = m;
      continue;
    }
    final (id, request) = m! as (int, Object?);
    try {
      final v = await handler(request);
      results!.send(_Reply(id, v, null, null));
    } on Object catch (e, s) {
      results!.send(_Reply(id, null, '$e', '$s'));
    }
  }
}
