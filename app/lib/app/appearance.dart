import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Appearance inputs that come from the platform rather than settings,
/// overridden in main.dart: Android Material You schemes (`dynamic_color`,
/// CORE-007) today; lane C4 adds whether the Windows runner applied Mica
/// and the platform "reduce transparency" preference.
@immutable
final class PlatformAppearance {
  const PlatformAppearance({
    this.dynamicLight,
    this.dynamicDark,
    this.micaActive = false,
    this.reduceTransparency = false,
  });

  final ColorScheme? dynamicLight;
  final ColorScheme? dynamicDark;
  final bool micaActive;
  final bool reduceTransparency;

  @override
  bool operator ==(Object other) =>
      other is PlatformAppearance &&
      other.dynamicLight == dynamicLight &&
      other.dynamicDark == dynamicDark &&
      other.micaActive == micaActive &&
      other.reduceTransparency == reduceTransparency;

  @override
  int get hashCode =>
      Object.hash(dynamicLight, dynamicDark, micaActive, reduceTransparency);
}

final platformAppearanceProvider = Provider<PlatformAppearance>(
  (ref) => const PlatformAppearance(),
);

/// The theme-relevant settings, resolved (CORE-007).
@immutable
final class ThemeSettings {
  const ThemeSettings({
    required this.family,
    required this.themeMode,
    required this.amoled,
    required this.forceHighContrast,
    required this.dynamicColor,
    required this.modeAccents,
    required this.accents,
    required this.platform,
    required this.reduceMotion,
    required this.reduceTransparency,
  });

  factory ThemeSettings.from(
    SettingsSnapshot s,
    PlatformAppearance platform,
    PlatformFamily family,
  ) => ThemeSettings(
    family: family,
    themeMode: s.get(CoreSettings.themeMode),
    amoled: s.get(CoreSettings.amoled),
    forceHighContrast: s.get(CoreSettings.highContrast) == SystemOrOn.on,
    dynamicColor: s.get(CoreSettings.dynamicColor),
    modeAccents: s.get(CoreSettings.modeAccents),
    accents: {
      MediaMode.video: s.get(CoreSettings.accentVideo),
      MediaMode.music: s.get(CoreSettings.accentMusic),
      MediaMode.photos: s.get(CoreSettings.accentPhotos),
    },
    platform: platform,
    reduceMotion: s.get(CoreSettings.reduceMotion) == SystemOrOn.on,
    reduceTransparency:
        s.get(CoreSettings.reduceTransparency) == SystemOrOn.on ||
        platform.reduceTransparency,
  );

  final PlatformFamily family;
  final ThemeMode themeMode;
  final bool amoled;
  final bool forceHighContrast;
  final bool dynamicColor;
  final bool modeAccents;
  final Map<MediaMode, AccentChoice> accents;
  final PlatformAppearance platform;
  final bool reduceMotion;
  final bool reduceTransparency;

  /// Theme for [mode]. With per-mode accents off every mode uses the video
  /// accent. Material You replaces the accents when enabled and available.
  ThemeData theme(
    Brightness brightness, {
    MediaMode mode = MediaMode.video,
    bool highContrast = false,
  }) {
    final effectiveMode = modeAccents ? mode : MediaMode.video;
    final choice = accents[effectiveMode]!;
    final dynamicScheme = dynamicColor
        ? (brightness == Brightness.dark
              ? platform.dynamicDark
              : platform.dynamicLight)
        : null;
    return MediahroTheme.build(
      ThemeSpec(
        family: family,
        brightness: brightness,
        mode: effectiveMode,
        amoled: amoled && brightness == Brightness.dark,
        highContrast: highContrast || forceHighContrast,
        dynamicScheme: dynamicScheme,
        accent: choice.argb == null ? null : Color(choice.argb!),
        micaActive: platform.micaActive,
      ),
    );
  }

  KAccessibilityData get accessibility => KAccessibilityData(
    reduceMotion: reduceMotion,
    reduceTransparency: reduceTransparency,
    highContrast: forceHighContrast,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings &&
      other.family == family &&
      other.themeMode == themeMode &&
      other.amoled == amoled &&
      other.forceHighContrast == forceHighContrast &&
      other.dynamicColor == dynamicColor &&
      other.modeAccents == modeAccents &&
      mapEquals(other.accents, accents) &&
      other.platform == platform &&
      other.reduceMotion == reduceMotion &&
      other.reduceTransparency == reduceTransparency;

  @override
  int get hashCode => Object.hash(
    family,
    themeMode,
    amoled,
    forceHighContrast,
    dynamicColor,
    modeAccents,
    Object.hashAll(accents.values),
    platform,
    reduceMotion,
    reduceTransparency,
  );
}

/// Whether the Windows runner applied the Mica backdrop (CORE-007 W). Lane
/// C4 overrides this from its window facade; `mediahroRoot` keeps owning
/// [platformAppearanceProvider] for the dynamic colour schemes.
final micaActiveProvider = Provider<bool>((ref) => false);

/// The platform's "reduce transparency" accessibility preference (Apple
/// Reduce Transparency, Windows transparency effects off). Lane C4
/// overrides this from its platform facade (SYS-008).
final platformReduceTransparencyProvider = Provider<bool>((ref) => false);

final themeSettingsProvider = Provider<ThemeSettings>((ref) {
  final platform = ref.watch(platformAppearanceProvider);
  return ThemeSettings.from(
    ref.watch(settingsProvider),
    PlatformAppearance(
      dynamicLight: platform.dynamicLight,
      dynamicDark: platform.dynamicDark,
      micaActive: platform.micaActive || ref.watch(micaActiveProvider),
      reduceTransparency:
          platform.reduceTransparency ||
          ref.watch(platformReduceTransparencyProvider),
    ),
    platformFamilyFor(defaultTargetPlatform),
  );
});
