import 'dart:async';

import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/platform/background_work.dart';

/// Checks the subscriptions for new episodes while the app is closed
/// (POD-002, ADR-049), where the platform can wake it: Android through
/// WorkManager, iOS through a background refresh. Elsewhere the facade says
/// it is not available and the foreground refresh (when the library opens,
/// then about hourly while the app runs) is all there is.
///
/// Nothing is scheduled until the listener subscribes to a podcast, and the
/// schedule is cancelled again when the last one is removed. A wake-up
/// checks only on an unmetered connection, and every request still goes
/// through the network gateway.
final class PodcastBackgroundRefresh {
  PodcastBackgroundRefresh({
    required this.work,
    required this.service,
    this.interval = const Duration(hours: 3),
    this.minAge = const Duration(hours: 1),
  });

  /// The task id the OS reports back in [BackgroundWorkFacade.runs].
  static const taskId = 'podcast.refresh';

  final BackgroundWorkFacade work;
  final PodcastService service;

  /// How often the OS is asked to wake the app (a hint, never a promise).
  final Duration interval;

  /// A show checked more recently than this is left alone on a wake-up.
  final Duration minAge;

  StreamSubscription<String>? _runs;
  StreamSubscription<void>? _changes;
  bool _scheduled = false;
  bool _disposed = false;

  /// Starts listening for wake-ups and keeps the schedule in step with the
  /// subscriptions.
  Future<void> start() async {
    if (!await work.available || _disposed) return;
    _runs ??= work.runs.listen((id) {
      if (id == taskId) unawaited(_run());
    });
    _changes ??= service.changes.listen((_) => unawaited(_sync()));
    await _sync();
  }

  Future<void> _sync() async {
    if (_disposed) return;
    final any = (await service.shows()).isNotEmpty;
    if (any && !_scheduled) {
      _scheduled = true;
      await work.schedulePeriodic(
        taskId,
        interval,
        unmeteredOnly: true,
      );
    } else if (!any && _scheduled) {
      _scheduled = false;
      await work.cancel(taskId);
    }
  }

  Future<void> _run() async {
    var ok = false;
    try {
      final results = await service.refreshAll(minAge: minAge);
      // A feed that could not be reached is not worth an immediate retry;
      // only a run that failed outright is.
      ok = results.isEmpty || results.any((r) => r.ok);
    } on Object {
      ok = false;
    }
    await work.complete(taskId, success: ok);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _runs?.cancel();
    await _changes?.cancel();
  }
}
