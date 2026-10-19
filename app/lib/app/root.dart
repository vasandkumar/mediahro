import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/features/settings/core_sections.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// The widget main.dart runs, shared with integration tests so they launch
/// exactly what users get.
///
/// Material You schemes (Android 12+, CORE-007) reach the theme through
/// [platformAppearanceProvider]; they are used only when the user turns on
/// "Colours from wallpaper".
Widget mediahroRoot(
  SettingsStore settings, {
  List<Override> overrides = const [],
}) => DynamicColorBuilder(
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
      ...overrides,
    ],
    child: const MediahroApp(),
  ),
);
