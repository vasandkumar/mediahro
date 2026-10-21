import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/features/photos/photos_settings.dart';
import 'package:mediahro/features/settings/core_sections.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/subtitles/subtitle_style.dart';
import 'package:mediahro/features/video/video_settings.dart';

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
      platformAppearanceProvider.overrideWithValue(
        PlatformAppearance(dynamicLight: light, dynamicDark: dark),
      ),
      ..._sharedOverrides(settings, overrides),
    ],
    child: const MediahroApp(),
  ),
);

/// Provider overrides every app tree has, whether it runs in
/// [mediahroRoot] or in the container of [mediahroContainer].
List<Override> _sharedOverrides(
  SettingsStore settings,
  List<Override> overrides,
) => [
  settingsStoreProvider.overrideWithValue(settings),
  // Each lane's settings contributions are appended here.
  settingsContributionsProvider.overrideWithValue([
    ...coreSettingsContributions,
    ...videoSettingsContributions,
    ...subtitleSettingsContributions,
    ...photoSettingsContributions,
  ]),
  ...overrides,
];

/// The wallpaper colour schemes the widget tree learns about, handed to
/// [platformAppearanceProvider] in the shared container.
final _wallpaperSchemesProvider =
    NotifierProvider<_WallpaperSchemes, PlatformAppearance>(
      _WallpaperSchemes.new,
    );

class _WallpaperSchemes extends Notifier<PlatformAppearance> {
  @override
  PlatformAppearance build() => const PlatformAppearance();

  void update(ColorScheme? light, ColorScheme? dark) {
    final next = PlatformAppearance(dynamicLight: light, dynamicDark: dark);
    if (next != state) state = next;
  }
}

/// The app's one provider container, made before any widget exists so that
/// work which must not wait for a screen can start from it (ADR-049: a job
/// that wakes a closed app is listened for in `main`). Give it to
/// [mediahroApp] to show the app from the same container; every facade and
/// service then exists once. The caller owns the container.
ProviderContainer mediahroContainer(
  SettingsStore settings, {
  List<Override> overrides = const [],
}) => ProviderContainer(
  overrides: [
    ..._sharedOverrides(settings, overrides),
    platformAppearanceProvider.overrideWith(
      (ref) => ref.watch(_wallpaperSchemesProvider),
    ),
  ],
);

/// The widget `main.dart` runs: the app shown from [container] (see
/// [mediahroContainer]). Wallpaper colours (CORE-007) arrive after the first
/// frame, as they do in [mediahroRoot].
Widget mediahroApp(ProviderContainer container) => DynamicColorBuilder(
  builder: (light, dark) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      container.read(_wallpaperSchemesProvider.notifier).update(light, dark);
    });
    return UncontrolledProviderScope(
      container: container,
      child: const MediahroApp(),
    );
  },
);
