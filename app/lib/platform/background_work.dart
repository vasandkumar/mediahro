/// Periodic background work (POD-002 feed refresh, ADR-049).
///
/// The OS, not the app, decides when a scheduled task runs: `interval` is a
/// hint, never a guarantee. When the OS wakes the app for a task, the id is
/// emitted on [runs]; the Dart side does the work and then reports the outcome
/// with [complete] so the OS can release the wake-up.
///
/// Android: WorkManager `PeriodicWorkRequest` (minimum 15 minutes). iOS:
/// `BGAppRefreshTask`. macOS and Windows: tasks run only while the app is
/// open. Every network call made from a background run still goes through
/// `NetworkGateway` and the PRIV-004 allow-list, nothing is scheduled unless
/// the user enabled the feature that asks for it, and there are no analytics.
abstract interface class BackgroundWorkFacade {
  /// Asks the OS to wake the app for [id] about every [interval]. Scheduling
  /// an [id] again replaces the earlier request. Intervals the platform
  /// cannot honour (Android: under 15 minutes) are raised to its minimum.
  Future<void> schedulePeriodic(
    String id,
    Duration interval, {
    bool requiresNetwork = true,
    bool unmeteredOnly = false,
    bool requiresCharging = false,
  });

  /// Stops waking the app for [id]. Does nothing if [id] is not scheduled.
  Future<void> cancel(String id);

  /// The id of each task the OS woke the app for. After handling one, call
  /// [complete] with the same id.
  Stream<String> get runs;

  /// Tells the OS that the run for [id] has finished. [success] false asks the
  /// platform to retry later where it supports that.
  Future<void> complete(String id, {required bool success});

  /// False where the platform cannot wake a closed app, so tasks run only
  /// while the app is open and callers keep their foreground refresh.
  Future<bool> get available;
}

/// Default for platforms and tests with no native implementation (ADR-049):
/// foreground only. Scheduling does nothing and no wake-ups arrive.
final class UnsupportedBackgroundWork implements BackgroundWorkFacade {
  const UnsupportedBackgroundWork();

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
  Stream<String> get runs => const Stream<String>.empty();

  @override
  Future<void> complete(String id, {required bool success}) async {}

  @override
  Future<bool> get available async => false;
}
