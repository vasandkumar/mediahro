import 'dart:io';

import 'package:integration_test/integration_test.dart';

import 'support/c1_player.dart';

/// Lane C1 acceptance in the app on every platform (CI integration jobs
/// A/I/M/W): the player screen with resume, speed, frame step, A-B loop,
/// chapters, bookmarks, tracks and the info overlay; touch gestures on
/// Android and iOS.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  videoPlayerSuite(gestures: Platform.isAndroid || Platform.isIOS);
}
