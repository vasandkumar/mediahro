import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mediahro/app/media_wiring.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/app/services.dart';
import 'package:mediahro/features/library/widgets.dart'
    show openItemActionProvider;
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart'
    show photoRoutes;
import 'package:mediahro/features/video/player/bundled_shaders.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/platform/platform_bindings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opened before the first frame so it already has the user's theme,
  // language and last mode (CORE-001, CORE-007), and the network policy
  // reads the privacy switches (CORE-015, PRIV-004).
  final services = await AppServices.open();
  // Licence notices for the bundled shaders (CORE-013).
  unawaited(registerShaderLicences());
  runApp(
    mediahroRoot(
      services.settings,
      overrides: [
        ...services.overrides,
        ...platformOverrides(),
        ...musicOverrides,
        ...videoOverrides,
        openItemActionProvider.overrideWithValue(openItemByKind),
        appRoutesProvider.overrideWithValue([...videoRoutes, ...photoRoutes]),
      ],
    ),
  );
}
