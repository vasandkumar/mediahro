import 'package:flutter/material.dart' show ThemeMode;
import 'package:mediahro/features/settings/settings_store.dart';

/// Whether an accessibility preference follows the system or is forced on.
enum SystemOrOn { system, on }

/// Accent presets offered per mode (CORE-007). [brand] is the mode's own
/// accent (video blue, music coral, photos teal).
enum AccentChoice {
  brand(null),
  blue(0xFF3A5BFF),
  violet(0xFF7C4DFF),
  pink(0xFFE91E63),
  red(0xFFE53935),
  coral(0xFFFF7A59),
  amber(0xFFFFB300),
  green(0xFF43A047),
  teal(0xFF22C3A6);

  const AccentChoice(this.argb);

  /// Null for [brand].
  final int? argb;
}

/// Settings owned by lane B3 (shell, appearance, language, shortcuts,
/// privacy toggles). Other lanes declare theirs in their own folders.
abstract final class CoreSettings {
  static final SettingKey<ThemeMode> themeMode = SettingKey.enumeration(
    'appearance.themeMode',
    ThemeMode.values,
    defaultValue: ThemeMode.system,
  );
  static final SettingKey<bool> amoled = SettingKey.boolean(
    'appearance.amoled',
    defaultValue: false,
  );
  static final SettingKey<SystemOrOn> highContrast = SettingKey.enumeration(
    'appearance.highContrast',
    SystemOrOn.values,
    defaultValue: SystemOrOn.system,
  );

  /// Material You colours from the wallpaper (Android, opt-in).
  static final SettingKey<bool> dynamicColor = SettingKey.boolean(
    'appearance.dynamicColor',
    defaultValue: false,
  );

  /// Each mode its own accent (on) or the video accent everywhere (off).
  static final SettingKey<bool> modeAccents = SettingKey.boolean(
    'appearance.modeAccents',
    defaultValue: true,
  );
  static final SettingKey<AccentChoice> accentVideo = SettingKey.enumeration(
    'appearance.accentVideo',
    AccentChoice.values,
    defaultValue: AccentChoice.brand,
  );
  static final SettingKey<AccentChoice> accentMusic = SettingKey.enumeration(
    'appearance.accentMusic',
    AccentChoice.values,
    defaultValue: AccentChoice.brand,
  );
  static final SettingKey<AccentChoice> accentPhotos = SettingKey.enumeration(
    'appearance.accentPhotos',
    AccentChoice.values,
    defaultValue: AccentChoice.brand,
  );
  static final SettingKey<SystemOrOn> reduceMotion = SettingKey.enumeration(
    'appearance.reduceMotion',
    SystemOrOn.values,
    defaultValue: SystemOrOn.system,
  );
  static final SettingKey<SystemOrOn> reduceTransparency =
      SettingKey.enumeration(
        'appearance.reduceTransparency',
        SystemOrOn.values,
        defaultValue: SystemOrOn.system,
      );

  /// BCP 47 tag (`pt-BR`, `zh-Hans`) or empty for the system language.
  static final SettingKey<String> language = SettingKey.text(
    'appearance.language',
    defaultValue: '',
  );

  /// CORE-001: open in the mode used last.
  static final SettingKey<bool> restoreLastMode = SettingKey.boolean(
    'appearance.restoreLastMode',
    defaultValue: true,
  );

  /// Device-local shell state; never exported.
  static final SettingKey<String> lastMode = SettingKey.text(
    'shell.lastMode',
    defaultValue: '',
  );

  /// CORE-009 overrides: `shortcuts.<actionId>` → list of key specs (empty
  /// list = unbound). [platformDefault] means the platform's default keys.
  static SettingKey<List<String>> shortcut(String actionId) =>
      SettingKey.stringList(
        'shortcuts.$actionId',
        defaultValue: platformDefault,
      );

  static const List<String> platformDefault = ['@default'];

  /// PRIV-004 per-endpoint toggle; every endpoint starts off (PRIV-001).
  static SettingKey<bool> endpoint(String endpointId) =>
      SettingKey.boolean('privacy.endpoint.$endpointId', defaultValue: false);

  /// PRIV-001's third toggle: update checks beyond the store (direct
  /// builds' signed updater, CORE-012).
  static final SettingKey<bool> updateCheck = SettingKey.boolean(
    'privacy.updateCheck',
    defaultValue: false,
  );

  static List<SettingKey<Object>> get all => [
    themeMode,
    amoled,
    highContrast,
    dynamicColor,
    modeAccents,
    accentVideo,
    accentMusic,
    accentPhotos,
    reduceMotion,
    reduceTransparency,
    language,
    restoreLastMode,
    lastMode,
    updateCheck,
  ];
}
