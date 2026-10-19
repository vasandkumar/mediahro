import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/features/settings/core_sections.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loaded before the first frame so it already has the user's theme,
  // language and last mode (CORE-001, CORE-007).
  final settings = await SettingsStore.open();
  runApp(
    // Material You schemes on Android 12+ (CORE-007); used only when the user
    // turns on "Colours from wallpaper".
    DynamicColorBuilder(
      builder: (light, dark) => ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings),
          platformAppearanceProvider.overrideWithValue(
            PlatformAppearance(dynamicLight: light, dynamicDark: dark),
          ),
          // Each lane's settings contributions are appended here.
          settingsContributionsProvider.overrideWithValue([
            ...coreSettingsContributions,
          ]),
        ],
        child: const MediahroApp(),
      ),
    ),
  );
}
