import 'package:flutter/services.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/shortcuts/key_spec.dart';
import 'package:meta/meta.dart';

/// Where an action is active. Global actions work everywhere, including in
/// the player; scoped actions only while that scope has focus.
enum ShortcutScope { global, player, viewer }

/// Groups in the cheat sheet and the remapping list.
enum ShortcutCategory {
  general,
  playback,
  seeking,
  audio,
  subtitles,
  view;

  String title(AppLocalizations l10n) => switch (this) {
    general => l10n.appShortcutGroupGeneral,
    playback => l10n.appShortcutGroupPlayback,
    seeking => l10n.appShortcutGroupSeeking,
    audio => l10n.appShortcutGroupAudio,
    subtitles => l10n.appShortcutGroupSubtitles,
    view => l10n.appShortcutGroupView,
  };
}

/// A remappable keyboard action (CORE-009). Lanes bind handlers to [id]
/// with `ShortcutScopeWidget`; they never hard-code keys.
@immutable
final class ShortcutAction {
  const ShortcutAction({
    required this.id,
    required this.scope,
    required this.category,
    required this.label,
    required this.defaults,
    this.platformDefaults = const {},
  });

  final String id;
  final ShortcutScope scope;
  final ShortcutCategory category;
  final String Function(AppLocalizations l10n) label;

  /// Default keys on every platform (docs/06 §6.2).
  final List<KeySpec> defaults;

  /// Extra platform-convention keys (Cmd+Ctrl+F on macOS, F11 on Windows).
  final Map<AppPlatform, List<KeySpec>> platformDefaults;

  List<KeySpec> defaultsFor(AppPlatform p) => [
    ...defaults,
    ...?platformDefaults[p],
  ];

  @override
  bool operator ==(Object other) => other is ShortcutAction && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The default map from docs/06 §6.2 plus app-level actions. Player and
/// viewer handlers are bound by lanes C1–C3.
abstract final class ShortcutCatalog {
  static ShortcutAction _p(
    String id,
    ShortcutCategory c,
    String Function(AppLocalizations) label,
    List<KeySpec> keys, {
    Map<AppPlatform, List<KeySpec>> platform = const {},
  }) => ShortcutAction(
    id: 'player.$id',
    scope: ShortcutScope.player,
    category: c,
    label: label,
    defaults: keys,
    platformDefaults: platform,
  );

  static ShortcutAction _g(
    String id,
    String Function(AppLocalizations) label,
    List<KeySpec> keys,
  ) => ShortcutAction(
    id: 'app.$id',
    scope: ShortcutScope.global,
    category: ShortcutCategory.general,
    label: label,
    defaults: keys,
  );

  static const String cheatSheet = 'app.shortcutSheet';
  static const String openSettings = 'app.settings';
  static const String openFile = 'app.openFile';
  static const String openUrl = 'app.openUrl';
  static const String search = 'app.search';
  static const String modeVideo = 'app.modeVideo';
  static const String modeMusic = 'app.modeMusic';
  static const String modePhotos = 'app.modePhotos';

  static final List<ShortcutAction> all = [
    _g('shortcutSheet', (l) => l.appShortcutCheatSheet, [
      const KeySpec.character('?'),
    ]),
    _g('settings', (l) => l.appShortcutSettings, [
      const KeySpec(LogicalKeyboardKey.comma, primary: true),
    ]),
    _g('openFile', (l) => l.appShortcutOpenFile, [
      const KeySpec(LogicalKeyboardKey.keyO, primary: true),
    ]),
    _g('openUrl', (l) => l.appShortcutOpenUrl, [
      const KeySpec(LogicalKeyboardKey.keyU, primary: true),
    ]),
    _g('search', (l) => l.appShortcutSearch, [
      const KeySpec(LogicalKeyboardKey.keyF, primary: true),
    ]),
    _g('modeVideo', (l) => l.appShortcutModeVideo, [
      const KeySpec(LogicalKeyboardKey.digit1, primary: true),
    ]),
    _g('modeMusic', (l) => l.appShortcutModeMusic, [
      const KeySpec(LogicalKeyboardKey.digit2, primary: true),
    ]),
    _g('modePhotos', (l) => l.appShortcutModePhotos, [
      const KeySpec(LogicalKeyboardKey.digit3, primary: true),
    ]),
    _p('playPause', ShortcutCategory.playback, (l) => l.appShortcutPlayPause, [
      const KeySpec(LogicalKeyboardKey.space),
      const KeySpec(LogicalKeyboardKey.keyK),
    ]),
    _p('seekBack5', ShortcutCategory.seeking, (l) => l.appShortcutSeekBack5, [
      const KeySpec(LogicalKeyboardKey.arrowLeft),
    ]),
    _p(
      'seekForward5',
      ShortcutCategory.seeking,
      (l) => l.appShortcutSeekForward5,
      [const KeySpec(LogicalKeyboardKey.arrowRight)],
    ),
    _p('seekBack1', ShortcutCategory.seeking, (l) => l.appShortcutSeekBack1, [
      const KeySpec(LogicalKeyboardKey.arrowLeft, shift: true),
    ]),
    _p(
      'seekForward1',
      ShortcutCategory.seeking,
      (l) => l.appShortcutSeekForward1,
      [const KeySpec(LogicalKeyboardKey.arrowRight, shift: true)],
    ),
    _p('seekBack60', ShortcutCategory.seeking, (l) => l.appShortcutSeekBack60, [
      const KeySpec(LogicalKeyboardKey.arrowLeft, primary: true),
    ]),
    _p(
      'seekForward60',
      ShortcutCategory.seeking,
      (l) => l.appShortcutSeekForward60,
      [const KeySpec(LogicalKeyboardKey.arrowRight, primary: true)],
    ),
    _p('seekBack10', ShortcutCategory.seeking, (l) => l.appShortcutSeekBack10, [
      const KeySpec(LogicalKeyboardKey.keyJ),
    ]),
    _p(
      'seekForward10',
      ShortcutCategory.seeking,
      (l) => l.appShortcutSeekForward10,
      [const KeySpec(LogicalKeyboardKey.keyL)],
    ),
    for (var i = 1; i <= 9; i++)
      _p(
        'jump${i}0',
        ShortcutCategory.seeking,
        (l) => l.appShortcutJumpPercent(i * 10),
        [KeySpec(LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i))],
      ),
    _p('frameBack', ShortcutCategory.seeking, (l) => l.appShortcutFrameBack, [
      const KeySpec(LogicalKeyboardKey.comma),
    ]),
    _p(
      'frameForward',
      ShortcutCategory.seeking,
      (l) => l.appShortcutFrameForward,
      [const KeySpec(LogicalKeyboardKey.period)],
    ),
    _p('abLoopSet', ShortcutCategory.seeking, (l) => l.appShortcutAbLoopSet, [
      const KeySpec(LogicalKeyboardKey.keyB),
    ]),
    _p(
      'abLoopClear',
      ShortcutCategory.seeking,
      (l) => l.appShortcutAbLoopClear,
      [const KeySpec(LogicalKeyboardKey.keyN)],
    ),
    _p('speedDown', ShortcutCategory.playback, (l) => l.appShortcutSpeedDown, [
      const KeySpec(LogicalKeyboardKey.bracketLeft),
    ]),
    _p('speedUp', ShortcutCategory.playback, (l) => l.appShortcutSpeedUp, [
      const KeySpec(LogicalKeyboardKey.bracketRight),
    ]),
    _p(
      'speedReset',
      ShortcutCategory.playback,
      (l) => l.appShortcutSpeedReset,
      [const KeySpec(LogicalKeyboardKey.backspace)],
    ),
    _p('volumeUp', ShortcutCategory.audio, (l) => l.appShortcutVolumeUp, [
      const KeySpec(LogicalKeyboardKey.arrowUp),
    ]),
    _p('volumeDown', ShortcutCategory.audio, (l) => l.appShortcutVolumeDown, [
      const KeySpec(LogicalKeyboardKey.arrowDown),
    ]),
    _p('mute', ShortcutCategory.audio, (l) => l.appShortcutMute, [
      const KeySpec(LogicalKeyboardKey.keyM),
    ]),
    _p('audioCycle', ShortcutCategory.audio, (l) => l.appShortcutAudioCycle, [
      const KeySpec(LogicalKeyboardKey.keyA),
    ]),
    _p(
      'audioDelayMinus',
      ShortcutCategory.audio,
      (l) => l.appShortcutAudioDelayMinus,
      [const KeySpec(LogicalKeyboardKey.keyC)],
    ),
    _p(
      'audioDelayPlus',
      ShortcutCategory.audio,
      (l) => l.appShortcutAudioDelayPlus,
      [const KeySpec(LogicalKeyboardKey.keyV)],
    ),
    _p(
      'subtitleCycle',
      ShortcutCategory.subtitles,
      (l) => l.appShortcutSubtitleCycle,
      [const KeySpec(LogicalKeyboardKey.keyS)],
    ),
    _p(
      'subtitleToggle',
      ShortcutCategory.subtitles,
      (l) => l.appShortcutSubtitleToggle,
      [const KeySpec(LogicalKeyboardKey.keyS, shift: true)],
    ),
    _p(
      'subtitleDelayMinus',
      ShortcutCategory.subtitles,
      (l) => l.appShortcutSubtitleDelayMinus,
      [const KeySpec(LogicalKeyboardKey.keyZ)],
    ),
    _p(
      'subtitleDelayPlus',
      ShortcutCategory.subtitles,
      (l) => l.appShortcutSubtitleDelayPlus,
      [const KeySpec(LogicalKeyboardKey.keyX)],
    ),
    _p(
      'fullscreen',
      ShortcutCategory.view,
      (l) => l.appShortcutFullscreen,
      [const KeySpec(LogicalKeyboardKey.keyF)],
      platform: const {
        AppPlatform.macos: [
          KeySpec(LogicalKeyboardKey.keyF, primary: true, control: true),
        ],
        AppPlatform.windows: [KeySpec(LogicalKeyboardKey.f11)],
      },
    ),
    _p(
      'exitFullscreen',
      ShortcutCategory.view,
      (l) => l.appShortcutExitFullscreen,
      [const KeySpec(LogicalKeyboardKey.escape)],
    ),
    _p('info', ShortcutCategory.view, (l) => l.appShortcutInfo, [
      const KeySpec(LogicalKeyboardKey.keyI),
    ]),
    _p('pip', ShortcutCategory.view, (l) => l.appShortcutPip, [
      const KeySpec(LogicalKeyboardKey.keyP),
    ]),
    _p('alwaysOnTop', ShortcutCategory.view, (l) => l.appShortcutAlwaysOnTop, [
      const KeySpec(LogicalKeyboardKey.keyT),
    ]),
    _p('screenshot', ShortcutCategory.view, (l) => l.appShortcutScreenshot, [
      const KeySpec(LogicalKeyboardKey.keyS, primary: true),
    ]),
  ];
}
