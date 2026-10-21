import 'package:mediahro/platform/android/gen/background_api.pigeon.dart'
    hide runs;
import 'package:mediahro/platform/android/gen/background_api.pigeon.dart'
    as native
    show runs;
import 'package:mediahro/platform/background_work.dart';

/// [BackgroundWorkFacade] on Android (ADR-049): one unique WorkManager
/// periodic job per id (`background/BackgroundWorkModule.kt`). WorkManager's
/// floor is 15 minutes, so a shorter interval is raised to it; scheduling an id
/// again replaces its job. When the OS runs a job the app's engine is started
/// without a screen if it is not open, and the id arrives on [runs]; the job is
/// retried later unless [complete] reports success. [runs] must be listened to
/// as soon as the app starts, or a job started while the app is closed gives up.
final class AndroidBackgroundWork implements BackgroundWorkFacade {
  AndroidBackgroundWork({
    BackgroundWorkHostApi? api,
    Stream<String> Function()? events,
  }) : _api = api ?? BackgroundWorkHostApi(),
       _events = events ?? native.runs;

  final BackgroundWorkHostApi _api;
  final Stream<String> Function() _events;

  @override
  Future<void> schedulePeriodic(
    String id,
    Duration interval, {
    bool requiresNetwork = true,
    bool unmeteredOnly = false,
    bool requiresCharging = false,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    return _api.schedulePeriodic(
      id,
      interval.inMilliseconds,
      requiresNetwork,
      unmeteredOnly,
      requiresCharging,
    );
  }

  @override
  Future<void> cancel(String id) => _api.cancel(id);

  @override
  Stream<String> get runs => _events();

  @override
  Future<void> complete(String id, {required bool success}) =>
      _api.complete(id, success);

  @override
  Future<bool> get available => _api.available();
}
