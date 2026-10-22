import 'package:flutter/material.dart' show ThemeMode;
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/locales.dart';
import 'package:mediahro/features/settings/about/about_panel.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/privacy/privacy_dashboard.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/shortcut_editor.dart';

String _systemOrOn(AppLocalizations l10n, SystemOrOn v) => switch (v) {
  SystemOrOn.system => l10n.settingsFollowSystem,
  SystemOrOn.on => l10n.settingsOn,
};

String accentLabel(AppLocalizations l10n, AccentChoice c) => switch (c) {
  AccentChoice.brand => l10n.settingsAccentBrand,
  AccentChoice.blue => l10n.settingsAccentBlue,
  AccentChoice.violet => l10n.settingsAccentViolet,
  AccentChoice.pink => l10n.settingsAccentPink,
  AccentChoice.red => l10n.settingsAccentRed,
  AccentChoice.coral => l10n.settingsAccentCoral,
  AccentChoice.amber => l10n.settingsAccentAmber,
  AccentChoice.green => l10n.settingsAccentGreen,
  AccentChoice.teal => l10n.settingsAccentTeal,
};

/// B3's sections: Appearance (CORE-007, CORE-008, CORE-001), Shortcuts
/// (CORE-009), Privacy (CORE-015).
final List<SettingsContribution> coreSettingsContributions = [
  SettingsContribution(
    section: SettingsSectionId.appearance,
    entries: [
      ChoiceSetting<ThemeMode>(
        key: CoreSettings.themeMode,
        options: ThemeMode.values,
        optionLabel: (l10n, v) => switch (v) {
          ThemeMode.system => l10n.settingsFollowSystem,
          ThemeMode.light => l10n.settingsThemeLight,
          ThemeMode.dark => l10n.settingsThemeDark,
        },
        title: (l) => l.settingsTheme,
        description: (l) => l.settingsThemeDescription,
        keywords: (l) => l.settingsThemeKeywords,
      ),
      ToggleSetting(
        key: CoreSettings.amoled,
        title: (l) => l.settingsAmoled,
        description: (l) => l.settingsAmoledDescription,
      ),
      ChoiceSetting<SystemOrOn>(
        key: CoreSettings.highContrast,
        options: SystemOrOn.values,
        optionLabel: _systemOrOn,
        title: (l) => l.settingsHighContrast,
        description: (l) => l.settingsHighContrastDescription,
      ),
      ToggleSetting(
        key: CoreSettings.dynamicColor,
        title: (l) => l.settingsDynamicColor,
        description: (l) => l.settingsDynamicColorDescription,
        platforms: const {AppPlatform.android},
      ),
      ToggleSetting(
        key: CoreSettings.modeAccents,
        title: (l) => l.settingsModeAccents,
        description: (l) => l.settingsModeAccentsDescription,
        keywords: (l) => l.settingsAccentKeywords,
      ),
      for (final (key, title) in [
        (
          CoreSettings.accentVideo,
          (AppLocalizations l) => l.settingsAccentVideo,
        ),
        (
          CoreSettings.accentMusic,
          (AppLocalizations l) => l.settingsAccentMusic,
        ),
        (
          CoreSettings.accentPhotos,
          (AppLocalizations l) => l.settingsAccentPhotos,
        ),
      ])
        ChoiceSetting<AccentChoice>(
          key: key,
          options: AccentChoice.values,
          optionLabel: accentLabel,
          title: title,
          description: (l) => l.settingsAccentDescription,
          keywords: (l) => l.settingsAccentKeywords,
          advanced: true,
        ),
      ChoiceSetting<String>(
        key: CoreSettings.language,
        options: const ['', ...appLanguageTags],
        optionLabel: (l10n, tag) =>
            tag.isEmpty ? l10n.settingsFollowSystem : languageEndonym(tag),
        title: (l) => l.settingsLanguage,
        description: (l) => l.settingsLanguageDescription,
        keywords: (l) => l.settingsLanguageKeywords,
      ),
      ToggleSetting(
        key: CoreSettings.restoreLastMode,
        title: (l) => l.settingsRestoreLastMode,
        description: (l) => l.settingsRestoreLastModeDescription,
      ),
      ChoiceSetting<SystemOrOn>(
        key: CoreSettings.reduceMotion,
        options: SystemOrOn.values,
        optionLabel: _systemOrOn,
        title: (l) => l.settingsReduceMotion,
        description: (l) => l.settingsReduceMotionDescription,
        advanced: true,
      ),
      ChoiceSetting<SystemOrOn>(
        key: CoreSettings.reduceTransparency,
        options: SystemOrOn.values,
        optionLabel: _systemOrOn,
        title: (l) => l.settingsReduceTransparency,
        description: (l) => l.settingsReduceTransparencyDescription,
        advanced: true,
      ),
    ],
  ),
  SettingsContribution(
    section: SettingsSectionId.shortcuts,
    entries: [
      CustomSetting(
        id: 'shortcuts.editor',
        title: (l) => l.settingsSectionShortcuts,
        description: (l) => l.settingsSectionShortcutsDescription,
        keywords: (l) => l.settingsShortcutsKeywords,
        builder: (context, highlight) => ShortcutEditor(highlight: highlight),
      ),
    ],
  ),
  SettingsContribution(
    section: SettingsSectionId.privacy,
    entries: [
      CustomSetting(
        id: 'privacy.dashboard',
        title: (l) => l.settingsPrivacyDashboard,
        description: (l) => l.settingsSectionPrivacyDescription,
        keywords: (l) => l.settingsPrivacyKeywords,
        settingKeys: [CoreSettings.updateCheck],
        builder: (context, highlight) => PrivacyDashboard(highlight: highlight),
      ),
    ],
  ),
  SettingsContribution(
    section: SettingsSectionId.about,
    entries: [
      CustomSetting(
        id: 'about.build',
        title: (l) => l.settingsSectionAbout,
        description: (l) => l.settingsSectionAboutDescription,
        keywords: (l) => l.settingsAboutKeywords,
        builder: (context, highlight) => const AboutPanel(),
      ),
    ],
  ),
];
