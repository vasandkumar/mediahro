import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/subtitles/subtitle_speech.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Subtitle text size; `system` follows the caption preference (SUB-014).
enum SubSize {
  system(null),
  small(0.75),
  normal(1),
  large(1.3),
  larger(1.6),
  huge(2);

  const SubSize(this.scale);

  final double? scale;
}

enum SubColor {
  system(null),
  white(0xFFFFFFFF),
  yellow(0xFFFFE600),
  cyan(0xFF00E5FF),
  green(0xFF3DFF5A),
  magenta(0xFFFF4DFF);

  const SubColor(this.argb);

  final int? argb;
}

enum SubOutline {
  system(null),
  none(0),
  thin(1.5),
  normal(3),
  thick(5);

  const SubOutline(this.width);

  final double? width;
}

enum SubBackground { system, none, box, opaque }

enum SubFont {
  system(null),
  sans('sans-serif'),
  serif('serif'),
  mono('monospace');

  const SubFont(this.family);

  final String? family;
}

/// Vertical placement; 0 = bottom, 100 = top (`SubtitleStyle`).
enum SubPosition {
  system(null),
  bottom(0),
  raised(12),
  middle(50),
  top(100);

  const SubPosition(this.value);

  final double? value;
}

enum SubAlign {
  system(null),
  left(SubtitleAlignX.left),
  center(SubtitleAlignX.center),
  right(SubtitleAlignX.right);

  const SubAlign(this.alignX);

  final SubtitleAlignX? alignX;
}

/// The user's system caption style (docs/06 §7) as far as C1 uses it. C4's
/// caption facade (ADR request, see docs/lanes) fills it; until then it is
/// null and engine defaults apply where the user chose "System".
@immutable
final class CaptionPrefs {
  const CaptionPrefs({
    this.scale,
    this.foregroundArgb,
    this.backgroundArgb,
    this.edgeWidth,
    this.edgeArgb,
    this.fontFamily,
    this.shadowOffset,
    this.captionsOn = false,
  });

  final double? scale;
  final int? foregroundArgb;
  final int? backgroundArgb;

  /// Outline width; 0 for no edge.
  final double? edgeWidth;
  final int? edgeArgb;
  final String? fontFamily;

  /// Drop shadow distance; null for the engine default.
  final double? shadowOffset;

  /// The user turned captions on in the system: videos start with
  /// subtitles (docs/06 §7).
  final bool captionsOn;
}

/// Subtitle style settings (SUB-014, SUB-016). Every choice defaults to
/// "System": the system caption style where the platform reports one.
abstract final class SubtitleSettings {
  static final SettingKey<SubSize> size = SettingKey.enumeration(
    'subtitles.size',
    SubSize.values,
    defaultValue: SubSize.system,
  );
  static final SettingKey<SubColor> color = SettingKey.enumeration(
    'subtitles.color',
    SubColor.values,
    defaultValue: SubColor.system,
  );
  static final SettingKey<SubOutline> outline = SettingKey.enumeration(
    'subtitles.outline',
    SubOutline.values,
    defaultValue: SubOutline.system,
  );
  static final SettingKey<SubBackground> background = SettingKey.enumeration(
    'subtitles.background',
    SubBackground.values,
    defaultValue: SubBackground.system,
  );
  static final SettingKey<SubFont> font = SettingKey.enumeration(
    'subtitles.font',
    SubFont.values,
    defaultValue: SubFont.system,
  );
  static final SettingKey<SubPosition> position = SettingKey.enumeration(
    'subtitles.position',
    SubPosition.values,
    defaultValue: SubPosition.system,
  );
  static final SettingKey<SubAlign> align = SettingKey.enumeration(
    'subtitles.align',
    SubAlign.values,
    defaultValue: SubAlign.system,
  );

  /// Apply these choices to ASS/SSA subtitles too (their own styles win
  /// otherwise).
  static final SettingKey<bool> overrideAss = SettingKey.boolean(
    'subtitles.overrideAss',
    defaultValue: false,
  );

  /// Second subtitles (SUB-016): their own size and place.
  static final SettingKey<SubSize> secondarySize = SettingKey.enumeration(
    'subtitles.secondarySize',
    SubSize.values,
    defaultValue: SubSize.system,
  );
  static final SettingKey<bool> secondaryOnTop = SettingKey.boolean(
    'subtitles.secondaryOnTop',
    defaultValue: true,
  );

  static final List<SettingKey<Object>> styleKeys = [
    size,
    color,
    outline,
    background,
    font,
    position,
    align,
    overrideAss,
  ];
}

/// The engine style for the user's choices over the system caption style
/// (SUB-014): a choice other than "System" wins; "System" takes [system]'s
/// value or leaves the engine default.
SubtitleStyle subtitleStyleFor(SettingsSnapshot s, {CaptionPrefs? system}) {
  final background = s.get(SubtitleSettings.background);
  final systemBack = system?.backgroundArgb;
  final boxed = switch (background) {
    SubBackground.box || SubBackground.opaque => true,
    SubBackground.none => false,
    SubBackground.system => systemBack != null && (systemBack >> 24) != 0,
  };
  return SubtitleStyle(
    font: s.get(SubtitleSettings.font).family ?? system?.fontFamily,
    scale: s.get(SubtitleSettings.size).scale ?? system?.scale,
    colorArgb: s.get(SubtitleSettings.color).argb ?? system?.foregroundArgb,
    outlineWidth: s.get(SubtitleSettings.outline).width ?? system?.edgeWidth,
    outlineColorArgb: system?.edgeArgb,
    shadowOffset: system?.shadowOffset,
    backgroundArgb: switch (background) {
      SubBackground.box => 0x99000000,
      SubBackground.opaque => 0xFF000000,
      SubBackground.none => null,
      SubBackground.system => systemBack,
    },
    borderStyle: boxed
        ? SubtitleBorderStyle.backgroundBox
        : SubtitleBorderStyle.outlineAndShadow,
    verticalPosition: s.get(SubtitleSettings.position).value,
    alignX: s.get(SubtitleSettings.align).alignX,
    overrideAssStyles: s.get(SubtitleSettings.overrideAss),
  );
}

/// The second line's style (SUB-016): mpv only places it, so the player
/// draws its text at this scale.
double secondaryScale(SettingsSnapshot s, {CaptionPrefs? system}) =>
    s.get(SubtitleSettings.secondarySize).scale ?? system?.scale ?? 1;

// ------------------------------------------------------------ settings UI

String _sizeLabel(AppLocalizations l, SubSize v) => l.videoSubSize(v.name);
String _colorLabel(AppLocalizations l, SubColor v) => l.videoSubColor(v.name);
String _outlineLabel(AppLocalizations l, SubOutline v) =>
    l.videoSubOutline(v.name);
String _backgroundLabel(AppLocalizations l, SubBackground v) =>
    l.videoSubBackground(v.name);
String _fontLabel(AppLocalizations l, SubFont v) => l.videoSubFont(v.name);
String _positionLabel(AppLocalizations l, SubPosition v) =>
    l.videoSubPosition(v.name);
String _alignLabel(AppLocalizations l, SubAlign v) => l.videoSubAlign(v.name);

final subtitleSettingsContributions = [
  SettingsContribution(
    section: SettingsSectionId.subtitles,
    entries: [
      ChoiceSetting<SubSize>(
        key: SubtitleSettings.size,
        options: SubSize.values,
        optionLabel: _sizeLabel,
        title: (l) => l.videoSubSizeTitle,
        description: (l) => l.videoSubSystemDescription,
      ),
      ChoiceSetting<SubColor>(
        key: SubtitleSettings.color,
        options: SubColor.values,
        optionLabel: _colorLabel,
        title: (l) => l.videoSubColorTitle,
        description: (l) => l.videoSubSystemDescription,
      ),
      ChoiceSetting<SubOutline>(
        key: SubtitleSettings.outline,
        options: SubOutline.values,
        optionLabel: _outlineLabel,
        title: (l) => l.videoSubOutlineTitle,
        description: (l) => l.videoSubSystemDescription,
      ),
      ChoiceSetting<SubBackground>(
        key: SubtitleSettings.background,
        options: SubBackground.values,
        optionLabel: _backgroundLabel,
        title: (l) => l.videoSubBackgroundTitle,
        description: (l) => l.videoSubSystemDescription,
      ),
      ChoiceSetting<SubFont>(
        key: SubtitleSettings.font,
        options: SubFont.values,
        optionLabel: _fontLabel,
        title: (l) => l.videoSubFontTitle,
        description: (l) => l.videoSubSystemDescription,
      ),
      ChoiceSetting<SubPosition>(
        key: SubtitleSettings.position,
        options: SubPosition.values,
        optionLabel: _positionLabel,
        title: (l) => l.videoSubPositionTitle,
        description: (l) => l.videoSubPositionDescription,
      ),
      ChoiceSetting<SubAlign>(
        key: SubtitleSettings.align,
        options: SubAlign.values,
        optionLabel: _alignLabel,
        title: (l) => l.videoSubAlignTitle,
        description: (l) => l.videoSubAlignDescription,
        advanced: true,
      ),
      ToggleSetting(
        key: SubtitleSettings.overrideAss,
        title: (l) => l.videoSubOverrideAssTitle,
        description: (l) => l.videoSubOverrideAssDescription,
        advanced: true,
      ),
      ChoiceSetting<SubSize>(
        key: SubtitleSettings.secondarySize,
        options: SubSize.values,
        optionLabel: _sizeLabel,
        title: (l) => l.videoSubSecondarySizeTitle,
        description: (l) => l.videoSubSecondarySizeDescription,
      ),
      ToggleSetting(
        key: SubtitleSettings.secondaryOnTop,
        title: (l) => l.videoSubSecondaryOnTopTitle,
        description: (l) => l.videoSubSecondaryOnTopDescription,
      ),
      SliderSetting(
        key: SpeechSettings.rate,
        min: 0.5,
        max: 2,
        divisions: 6,
        valueLabel: (l, v) => l.videoSpeedValue(v),
        title: (l) => l.videoReadAloudRateTitle,
        description: (l) => l.videoReadAloudRateDescription,
        advanced: true,
      ),
    ],
  ),
];

/// The system caption style for subtitles; null until C4's caption facade
/// exists (ADR request). `videoOverrides` will point it at the facade.
final captionPrefsProvider = Provider<CaptionPrefs?>(
  (ref) => captionPrefsFrom(ref.watch(systemCaptionStyleProvider).value),
);

/// The system caption style and its changes (ADR-030); null where the
/// platform has no caption settings or no facade yet.
final systemCaptionStyleProvider = StreamProvider<SystemCaptionStyle?>((
  ref,
) async* {
  final CaptionStyleFacade facade;
  try {
    facade = ref.watch(captionStyleProvider);
  } on Object {
    yield null;
    return;
  }
  yield await facade.current();
  yield* facade.changes;
});

/// What C1 takes from the system caption style (SUB-014). The edge maps
/// to an outline or a shadow; an unset edge keeps the engine's outline so
/// text stays readable on bright pictures.
CaptionPrefs? captionPrefsFrom(SystemCaptionStyle? s) {
  if (s == null) return null;
  final box = s.backgroundArgb ?? s.windowArgb;
  return CaptionPrefs(
    scale: s.scale == 1 ? null : s.scale,
    foregroundArgb: s.foregroundArgb,
    backgroundArgb: box,
    edgeWidth: switch (s.edge) {
      CaptionEdge.none => null,
      CaptionEdge.outline => 2.5,
      CaptionEdge.raised || CaptionEdge.depressed => 1.5,
      CaptionEdge.dropShadow => 0,
    },
    shadowOffset: s.edge == CaptionEdge.dropShadow ? 2 : null,
    edgeArgb: s.edgeArgb,
    fontFamily: s.fontFamily,
    captionsOn: s.enabled,
  );
}
