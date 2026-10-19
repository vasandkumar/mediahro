import 'dart:async';

import 'package:mediahro_design/testing.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runWithTolerantGoldens(testMain);
