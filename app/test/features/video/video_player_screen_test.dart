import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/c1_player.dart';

void main() => videoPlayerSuite(
  gestures: true,
  touchVariant: TargetPlatformVariant.only(TargetPlatform.android),
);
