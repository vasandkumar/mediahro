import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/speed.dart';

/// Resume behaviour when an item with a saved position opens (VID-064).
enum ResumeMode { always, never }

/// Screen rotation in the player (VID-070).
enum VideoOrientation { followVideo, auto, landscape, portrait }

/// Playing on when the app goes to the background (VID-068).
enum BackgroundPlay { off, always }

/// What happens when an item ends (VID-064).
enum PostPlayback { stop, next, repeat, close, delete }

/// Video player settings (lane C1). The orchestrator lists
/// [videoSettingsContributions] in the app root.
abstract final class VideoSettings {
  static final SettingKey<SpeedMemory> speedMemory = SettingKey.enumeration(
    'video.speedMemory',
    SpeedMemory.values,
    defaultValue: SpeedMemory.perItem,
  );
  static final SettingKey<ResumeMode> resume = SettingKey.enumeration(
    'video.resume',
    ResumeMode.values,
    defaultValue: ResumeMode.always,
  );
  static final SettingKey<PostPlayback> afterPlayback = SettingKey.enumeration(
    'video.afterPlayback',
    PostPlayback.values,
    defaultValue: PostPlayback.next,
  );

  static final SettingKey<VideoOrientation> orientation =
      SettingKey.enumeration(
        'video.orientation',
        VideoOrientation.values,
        defaultValue: VideoOrientation.followVideo,
      );

  /// The one-time offer to allow access to a video's folder for its
  /// subtitles has been made (SUB-012).
  static final SettingKey<bool> subtitleAccessAsked = SettingKey.boolean(
    'video.subtitleAccessAsked',
    defaultValue: false,
  );

  /// Picture-in-picture when leaving the app while a video plays (VID-067,
  /// opt-in).
  static final SettingKey<bool> autoPip = SettingKey.boolean(
    'video.autoPip',
    defaultValue: false,
  );

  static final SettingKey<BackgroundPlay> backgroundPlay =
      SettingKey.enumeration(
        'video.backgroundPlay',
        BackgroundPlay.values,
        defaultValue: BackgroundPlay.off,
      );

  /// Turn the picture off while playing in the background (power saving).
  static final SettingKey<bool> backgroundVideoOff = SettingKey.boolean(
    'video.backgroundVideoOff',
    defaultValue: true,
  );

  /// Preferred audio and subtitle languages, in order (VID-065).
  static final SettingKey<List<String>> audioLanguages = SettingKey.stringList(
    'video.audioLanguages',
  );
  static final SettingKey<List<String>> subtitleLanguages =
      SettingKey.stringList('video.subtitleLanguages');

  /// A folder searched for subtitle files by video name (SUB-012), as a
  /// URI; empty for none.
  static final SettingKey<String> subtitleFolder = SettingKey.text(
    'video.subtitleFolder',
    defaultValue: '',
  );

  /// Double-tap seek step in seconds (VID-060: 5–60).
  static final SettingKey<int> doubleTapSeconds = SettingKey.integer(
    'video.doubleTapSeconds',
    defaultValue: 10,
    min: 5,
    max: 60,
  );

  /// Long-press speed (VID-060).
  static final SettingKey<double> longPressSpeed = SettingKey.decimal(
    'video.longPressSpeed',
    defaultValue: 2,
    min: 0.25,
    max: 4,
  );

  /// Gesture switches (VID-060); all on by default.
  static final SettingKey<bool> gestureSeek = SettingKey.boolean(
    'video.gesture.seek',
    defaultValue: true,
  );
  static final SettingKey<bool> gestureBrightness = SettingKey.boolean(
    'video.gesture.brightness',
    defaultValue: true,
  );
  static final SettingKey<bool> gestureVolume = SettingKey.boolean(
    'video.gesture.volume',
    defaultValue: true,
  );
  static final SettingKey<bool> gestureDoubleTap = SettingKey.boolean(
    'video.gesture.doubleTap',
    defaultValue: true,
  );
  static final SettingKey<bool> gestureLongPress = SettingKey.boolean(
    'video.gesture.longPress',
    defaultValue: true,
  );
  static final SettingKey<bool> gesturePinch = SettingKey.boolean(
    'video.gesture.pinch',
    defaultValue: true,
  );
  static final SettingKey<bool> gestureSubtitleDelay = SettingKey.boolean(
    'video.gesture.subtitleDelay',
    defaultValue: true,
  );

  /// Swipe sensitivity multiplier (VID-060).
  static final SettingKey<double> gestureSensitivity = SettingKey.decimal(
    'video.gesture.sensitivity',
    defaultValue: 1,
    min: 0.25,
    max: 4,
  );

  /// Seconds the "Next" card counts down before starting (0 = at once).
  static final SettingKey<int> nextCountdown = SettingKey.integer(
    'video.nextCountdown',
    defaultValue: 10,
    min: 0,
    max: 60,
  );
}

String _speedMemoryLabel(AppLocalizations l, SpeedMemory v) => switch (v) {
  SpeedMemory.perItem => l.videoSpeedMemoryPerItem,
  SpeedMemory.global => l.videoSpeedMemoryGlobal,
  SpeedMemory.off => l.videoSpeedMemoryOff,
};

String _resumeLabel(AppLocalizations l, ResumeMode v) => switch (v) {
  ResumeMode.always => l.videoResumeAlways,
  ResumeMode.never => l.videoResumeNever,
};

String _orientationLabel(AppLocalizations l, VideoOrientation v) => switch (v) {
  VideoOrientation.followVideo => l.videoOrientationFollow,
  VideoOrientation.auto => l.videoOrientationAuto,
  VideoOrientation.landscape => l.videoOrientationLandscape,
  VideoOrientation.portrait => l.videoOrientationPortrait,
};

String _backgroundLabel(AppLocalizations l, BackgroundPlay v) => switch (v) {
  BackgroundPlay.off => l.videoBackgroundOff,
  BackgroundPlay.always => l.videoBackgroundAlways,
};

String postPlaybackLabel(AppLocalizations l, PostPlayback v) => switch (v) {
  PostPlayback.stop => l.videoAfterPlaybackStop,
  PostPlayback.next => l.videoAfterPlaybackNext,
  PostPlayback.repeat => l.videoAfterPlaybackRepeat,
  PostPlayback.close => l.videoAfterPlaybackClose,
  PostPlayback.delete => l.videoAfterPlaybackDelete,
};

final videoSettingsContributions = [
  SettingsContribution(
    section: SettingsSectionId.video,
    entries: [
      ChoiceSetting<ResumeMode>(
        key: VideoSettings.resume,
        options: ResumeMode.values,
        optionLabel: _resumeLabel,
        title: (l) => l.videoResumeTitle,
        description: (l) => l.videoResumeDescription,
      ),
      ChoiceSetting<PostPlayback>(
        key: VideoSettings.afterPlayback,
        options: PostPlayback.values,
        optionLabel: postPlaybackLabel,
        title: (l) => l.videoAfterPlaybackTitle,
        description: (l) => l.videoAfterPlaybackDescription,
      ),
      ChoiceSetting<VideoOrientation>(
        key: VideoSettings.orientation,
        options: VideoOrientation.values,
        optionLabel: _orientationLabel,
        title: (l) => l.videoOrientationTitle,
        description: (l) => l.videoOrientationDescription,
        platforms: const {AppPlatform.android, AppPlatform.ios},
      ),
      ToggleSetting(
        key: VideoSettings.autoPip,
        title: (l) => l.videoAutoPipTitle,
        description: (l) => l.videoAutoPipDescription,
      ),
      ChoiceSetting<BackgroundPlay>(
        key: VideoSettings.backgroundPlay,
        options: BackgroundPlay.values,
        optionLabel: _backgroundLabel,
        title: (l) => l.videoBackgroundTitle,
        description: (l) => l.videoBackgroundDescription,
      ),
      ToggleSetting(
        key: VideoSettings.backgroundVideoOff,
        title: (l) => l.videoBackgroundVideoOffTitle,
        description: (l) => l.videoBackgroundVideoOffDescription,
        advanced: true,
      ),
      ChoiceSetting<SpeedMemory>(
        key: VideoSettings.speedMemory,
        options: SpeedMemory.values,
        optionLabel: _speedMemoryLabel,
        title: (l) => l.videoSpeedMemoryTitle,
        description: (l) => l.videoSpeedMemoryDescription,
      ),
      ChoiceSetting<int>(
        key: VideoSettings.nextCountdown,
        options: const [0, 5, 10, 15, 30],
        optionLabel: (l, v) => l.videoNextCountdownSeconds(v),
        title: (l) => l.videoNextCountdownTitle,
        description: (l) => l.videoNextCountdownDescription,
        advanced: true,
      ),
    ],
  ),
];
