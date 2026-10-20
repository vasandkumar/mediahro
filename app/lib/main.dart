import 'package:flutter/widgets.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/app/services.dart';
import 'package:mediahro/features/music/music_wiring.dart';
import 'package:mediahro/platform/platform_bindings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opened before the first frame so it already has the user's theme,
  // language and last mode (CORE-001, CORE-007), and the network policy
  // reads the privacy switches (CORE-015, PRIV-004).
  final services = await AppServices.open();
  runApp(
    mediahroRoot(
      services.settings,
      overrides: [
        ...services.overrides,
        ...platformOverrides(),
        ...musicOverrides,
      ],
    ),
  );
}
