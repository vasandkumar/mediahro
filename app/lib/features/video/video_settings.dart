import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/speed.dart';

/// Resume behaviour when an item with a saved position opens (VID-064).
enum ResumeMode { always, never }

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

  /// Preferred audio and subtitle languages, in order (VID-065).
  static final SettingKey<List<String>> audioLanguages = SettingKey.stringList(
    'video.audioLanguages',
  );
  static final SettingKey<List<String>> subtitleLanguages =
      SettingKey.stringList('video.subtitleLanguages');

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
