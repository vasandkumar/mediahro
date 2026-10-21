import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Does the work of one scheduled job and says whether it worked: true is a
/// success, false asks the OS to retry later. A handler that throws counts as
/// a failure.
typedef BackgroundJobHandler = Future<bool> Function();

/// Receives the jobs the OS wakes the app for (ADR-049) and gives each to the
/// handler its feature registered.
///
/// Features register a handler per job id and schedule the job through
/// `backgroundWorkProvider`. For every id on the facade's `runs` this calls the
/// handler and then `complete`, so the OS can release the wake-up. An id with
/// no handler (a job from an older version, or a feature switched off since)
/// completes as a success, so the OS does not retry it for ever.
///
/// It must listen from the first moment of the app: when the OS wakes a closed
/// app the engine starts without a screen and the job waits for this listener.
final class BackgroundWorkDispatcher {
  BackgroundWorkDispatcher(
    this._work, {
    this.handlerTimeout = const Duration(minutes: 7),
  });

  final BackgroundWorkFacade _work;

  /// The most a handler may take. The OS stops a job after 10 minutes, so a
  /// handler that is still running at this point is reported as a failure.
  final Duration handlerTimeout;

  final _handlers = <String, BackgroundJobHandler>{};
  StreamSubscription<String>? _runs;

  /// Registers [handler] for [id], replacing an earlier one.
  void register(String id, BackgroundJobHandler handler) =>
      _handlers[id] = handler;

  /// Removes the handler of [id]; the id then completes as a success.
  void unregister(String id) => _handlers.remove(id);

  /// Starts listening to the OS. Does nothing when already started.
  void start() {
    _runs ??= _work.runs.listen(
      (id) => unawaited(_run(id)),
      // A facade whose stream fails must not take the app down.
      onError: (Object _) {},
    );
  }

  Future<void> _run(String id) async {
    var success = true;
    final handler = _handlers[id];
    if (handler != null) {
      try {
        // Through an async function: a handler that throws at once, or whose
        // Future has a narrower runtime type than Future<bool> (an async closure
        // that only throws is a Future<Never>), then times out like any other.
        Future<bool> call() async => await handler();
        success = await call().timeout(handlerTimeout, onTimeout: () => false);
      } on Object {
        success = false;
      }
    }
    try {
      await _work.complete(id, success: success);
    } on Object {
      // The OS gave up on the job already; there is nobody left to tell.
    }
  }

  Future<void> dispose() async {
    await _runs?.cancel();
    _runs = null;
  }
}

/// The app's dispatcher. Read once at app start
/// (`ref.read(backgroundWorkDispatcherProvider)`) so it listens at once, in the
/// normal start and in the engine the OS starts without a screen (ADR-036).
final backgroundWorkDispatcherProvider = Provider<BackgroundWorkDispatcher>((
  ref,
) {
  final dispatcher = BackgroundWorkDispatcher(ref.watch(backgroundWorkProvider))
    ..start();
  ref.onDispose(dispatcher.dispose);
  return dispatcher;
});
