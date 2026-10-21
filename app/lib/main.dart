import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mediahro/app/background_work_dispatcher.dart';
import 'package:mediahro/app/media_wiring.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/app/services.dart';
import 'package:mediahro/features/library/widgets.dart'
    show openItemActionProvider;
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/features/photos/map/map_licences.dart';
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
  // Licence notices for the photo map data (IMG-007, CORE-013).
  registerMapLicences();
  // The app's one container, made before any widget so work that must not wait
  // for a screen can start from it. ADR-049: it listens for scheduled jobs at
  // once; when the OS wakes a closed app the engine starts without a screen
  // (ADR-036) and the job waits for this listener, whether or not a widget
  // tree is ever built there.
  final container = mediahroContainer(
    services.settings,
    overrides: [
      ...services.overrides,
      ...platformOverrides(),
      ...musicOverrides,
      ...videoOverrides,
      openItemActionProvider.overrideWithValue(openItemByKind),
      appRoutesProvider.overrideWithValue([...videoRoutes, ...photoRoutes]),
    ],
  )..read(backgroundWorkDispatcherProvider);
  runApp(mediahroApp(container));
}
