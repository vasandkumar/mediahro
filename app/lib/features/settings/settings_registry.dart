import 'package:flutter/widgets.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Settings sections in display order (docs/06 §2).
enum SettingsSectionId {
  playback(KIcon.playback),
  video(KIcon.video),
  audio(KIcon.audioTrack),
  subtitles(KIcon.subtitles),
  photos(KIcon.photos),
  library(KIcon.library),
  sources(KIcon.sources),
  appearance(KIcon.appearance),
  shortcuts(KIcon.keyboard),
  privacy(KIcon.privacy),
  support(KIcon.support),
  about(KIcon.about);

  const SettingsSectionId(this.icon);

  final KIcon icon;

  String title(AppLocalizations l10n) => switch (this) {
    playback => l10n.settingsSectionPlayback,
    video => l10n.settingsSectionVideo,
    audio => l10n.settingsSectionAudio,
    subtitles => l10n.settingsSectionSubtitles,
    photos => l10n.settingsSectionPhotos,
    library => l10n.settingsSectionLibrary,
    sources => l10n.settingsSectionSources,
    appearance => l10n.settingsSectionAppearance,
    shortcuts => l10n.settingsSectionShortcuts,
    privacy => l10n.settingsSectionPrivacy,
    support => l10n.settingsSectionSupport,
    about => l10n.settingsSectionAbout,
  };

  String description(AppLocalizations l10n) => switch (this) {
    playback => l10n.settingsSectionPlaybackDescription,
    video => l10n.settingsSectionVideoDescription,
    audio => l10n.settingsSectionAudioDescription,
    subtitles => l10n.settingsSectionSubtitlesDescription,
    photos => l10n.settingsSectionPhotosDescription,
    library => l10n.settingsSectionLibraryDescription,
    sources => l10n.settingsSectionSourcesDescription,
    appearance => l10n.settingsSectionAppearanceDescription,
    shortcuts => l10n.settingsSectionShortcutsDescription,
    privacy => l10n.settingsSectionPrivacyDescription,
    support => l10n.settingsSectionSupportDescription,
    about => l10n.settingsSectionAboutDescription,
  };
}

/// Localised text read from the merged ARB files (each lane's own keys).
typedef LocalizedText = String Function(AppLocalizations l10n);

/// One row in a settings section. Every row has a title and a one-line
/// description (CORE-006 AC).
@immutable
sealed class SettingEntry {
  const SettingEntry({
    required this.id,
    required this.title,
    required this.description,
    this.keywords,
    this.advanced = false,
    this.platforms,
    this.visibleWhen,
  });

  /// Stable id (usually the key id) used for search results and tests.
  final String id;
  final LocalizedText title;
  final LocalizedText description;

  /// Extra search terms ("dark, night, black").
  final LocalizedText? keywords;

  /// Listed in the collapsed "Advanced" group of the section.
  final bool advanced;

  /// Hidden on other platforms (docs/06 §3.5: per-platform rows hidden when
  /// not applicable). Null = every platform.
  final Set<AppPlatform>? platforms;

  /// Hidden unless this returns true (flavour-dependent rows).
  final bool Function(Capabilities caps)? visibleWhen;

  bool isVisible(Capabilities caps) =>
      (platforms == null || platforms!.contains(caps.platform)) &&
      (visibleWhen?.call(caps) ?? true);

  /// The keys this row writes, for managed-state lookups and import checks.
  List<SettingKey<Object>> get keys;
}

final class ToggleSetting extends SettingEntry {
  ToggleSetting({
    required this.key,
    required super.title,
    required super.description,
    super.keywords,
    super.advanced,
    super.platforms,
    super.visibleWhen,
  }) : super(id: key.id);

  final SettingKey<bool> key;

  @override
  List<SettingKey<Object>> get keys => [key];
}

/// A value picked from a fixed list (shown in a sheet).
final class ChoiceSetting<T extends Object> extends SettingEntry {
  ChoiceSetting({
    required this.key,
    required this.options,
    required this.optionLabel,
    required super.title,
    required super.description,
    super.keywords,
    super.advanced,
    super.platforms,
    super.visibleWhen,
  }) : super(id: key.id);

  final SettingKey<T> key;
  final List<T> options;
  final String Function(AppLocalizations l10n, T value) optionLabel;

  @override
  List<SettingKey<Object>> get keys => [key];

  String currentLabel(SettingsSnapshot s, AppLocalizations l10n) =>
      optionLabel(l10n, s.get(key));

  /// Label, whether selected, and how to select it.
  List<(String, bool, void Function(SettingsStore))> choices(
    SettingsSnapshot s,
    AppLocalizations l10n,
  ) => [
    for (final o in options)
      (optionLabel(l10n, o), s.get(key) == o, (store) => store.set(key, o)),
  ];
}

final class SliderSetting extends SettingEntry {
  SliderSetting({
    required this.key,
    required this.min,
    required this.max,
    required this.valueLabel,
    required super.title,
    required super.description,
    this.divisions,
    super.keywords,
    super.advanced,
    super.platforms,
    super.visibleWhen,
  }) : super(id: key.id);

  final SettingKey<double> key;
  final double min;
  final double max;
  final int? divisions;
  final String Function(AppLocalizations l10n, double value) valueLabel;

  @override
  List<SettingKey<Object>> get keys => [key];
}

/// Opens a route (sub-page or another lane's screen).
final class LinkSetting extends SettingEntry {
  const LinkSetting({
    required super.id,
    required this.location,
    required super.title,
    required super.description,
    super.keywords,
    super.advanced,
    super.platforms,
    super.visibleWhen,
  });

  /// go_router location.
  final String location;

  @override
  List<SettingKey<Object>> get keys => const [];
}

/// Free-form content (the shortcut editor, the privacy dashboard).
final class CustomSetting extends SettingEntry {
  const CustomSetting({
    required super.id,
    required this.builder,
    required super.title,
    required super.description,
    this.settingKeys = const [],
    super.keywords,
    super.advanced,
    super.platforms,
    super.visibleWhen,
  });

  final Widget Function(BuildContext context, String? highlight) builder;
  final List<SettingKey<Object>> settingKeys;

  @override
  List<SettingKey<Object>> get keys => settingKeys;
}

/// A lane's rows for one section. Lanes define contributions in their own
/// folders; the orchestrator lists them in `settingsContributionsProvider`
/// (main.dart), so no lane edits another lane's files.
@immutable
final class SettingsContribution {
  const SettingsContribution({
    required this.section,
    required this.entries,
    this.order = 0,
  });

  final SettingsSectionId section;
  final List<SettingEntry> entries;

  /// Position among contributions to the same section (lower first).
  final int order;
}

@immutable
final class SettingsSectionView {
  const SettingsSectionView(this.id, this.entries);

  final SettingsSectionId id;
  final List<SettingEntry> entries;

  List<SettingEntry> get basic => entries.where((e) => !e.advanced).toList();
  List<SettingEntry> get advanced => entries.where((e) => e.advanced).toList();
}

@immutable
final class SettingsSearchHit {
  const SettingsSearchHit(this.section, this.entry);

  final SettingsSectionId section;
  final SettingEntry entry;
}

/// Merges contributions into sections and searches them.
@immutable
final class SettingsRegistry {
  SettingsRegistry(List<SettingsContribution> contributions, this.caps)
    : _contributions = [...contributions]
        ..sort((a, b) => a.order.compareTo(b.order));

  final List<SettingsContribution> _contributions;
  final Capabilities caps;

  /// Sections with at least one visible row, in docs/06 order.
  List<SettingsSectionView> get sections => [
    for (final id in SettingsSectionId.values)
      if (section(id) case final s? when s.entries.isNotEmpty) s,
  ];

  SettingsSectionView? section(SettingsSectionId id) {
    final entries = [
      for (final c in _contributions)
        if (c.section == id)
          for (final e in c.entries)
            if (e.isVisible(caps)) e,
    ];
    return entries.isEmpty ? null : SettingsSectionView(id, entries);
  }

  /// Every key any row writes (import validation).
  List<SettingKey<Object>> get keys => [
    for (final c in _contributions)
      for (final e in c.entries) ...e.keys,
  ];

  /// Case- and accent-insensitive search over titles, descriptions,
  /// keywords and section names. Every word must match.
  List<SettingsSearchHit> search(String query, AppLocalizations l10n) {
    final words = fold(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    return [
      for (final s in sections)
        for (final e in s.entries)
          if (_matches(words, s.id, e, l10n)) SettingsSearchHit(s.id, e),
    ];
  }

  bool _matches(
    List<String> words,
    SettingsSectionId section,
    SettingEntry e,
    AppLocalizations l10n,
  ) {
    final hay = fold(
      [
        e.title(l10n),
        e.description(l10n),
        e.keywords?.call(l10n) ?? '',
        section.title(l10n),
      ].join(' '),
    );
    return words.every(hay.contains);
  }

  /// Lower-cases and strips common Latin diacritics so "contraste" finds
  /// "Contraste" and "senal" finds "señal".
  static String fold(String s) {
    final b = StringBuffer();
    for (final rune in s.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      b.write(_fold[ch] ?? ch);
    }
    return b.toString();
  }

  static const Map<String, String> _fold = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ā': 'a',
    'ç': 'c',
    'ć': 'c',
    'č': 'c',
    'ď': 'd',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ē': 'e',
    'ě': 'e',
    'ğ': 'g',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ī': 'i',
    'ı': 'i',
    'ł': 'l',
    'ñ': 'n',
    'ń': 'n',
    'ň': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'ō': 'o',
    'ř': 'r',
    'ś': 's',
    'š': 's',
    'ş': 's',
    'ß': 'ss',
    'ť': 't',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ū': 'u',
    'ů': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ž': 'z',
    'ź': 'z',
    'ż': 'z',
  };
}
