import 'package:flutter/foundation.dart';
import 'package:mediahro/app/background_work_dispatcher.dart';

/// The job the debug receiver leaves scheduled (`DebugJobReceiver.kt`, ADR-049).
const debugLeaveJobId = 'debug.leave';

/// Answers the debug job in a debug build: logs `bg: ran <id>` and reports
/// success. QA schedules the job, swipes the app away and runs it with
/// `cmd jobscheduler run -f com.mediahro.app <job id>`; the line in the log
/// shows the OS woke the app, the engine started without a screen and Dart
/// answered. Called from `main` behind `kDebugMode`, so it is absent from
/// profile and release builds.
void registerDebugBackgroundJob(
  BackgroundWorkDispatcher dispatcher, {
  void Function(String line) log = _print,
}) {
  dispatcher.register(debugLeaveJobId, () async {
    log('bg: ran $debugLeaveJobId');
    return true;
  });
}

void _print(String line) => debugPrint(line);
