import 'dart:async';

import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/subtitles/subtitle_text_source.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Reading subtitles aloud (SUB-040).
abstract final class SpeechSettings {
  static final SettingKey<bool> readAloud = SettingKey.boolean(
    'subtitles.readAloud',
    defaultValue: false,
  );

  /// Relative to the system speech rate.
  static final SettingKey<double> rate = SettingKey.decimal(
    'subtitles.readAloudRate',
    defaultValue: 1,
    min: 0.5,
    max: 2,
  );
}

/// Speaks each new subtitle line through the system voice
/// (`SpeechSynthesisFacade`, SUB-040), in the track's language. A new line
/// interrupts the previous one, so speech never falls behind the video.
/// Nothing is spoken while paused.
final class SubtitleSpeaker {
  SubtitleSpeaker({
    required this.source,
    required this.speech,
    required this.settings,
  }) {
    source.addListener(_onCue);
  }

  final SubtitleTextSource source;
  final SpeechSynthesisFacade speech;
  final SettingsStore settings;
  Object? _last;

  bool get enabled => settings.get(SpeechSettings.readAloud);

  set enabled(bool on) {
    settings.set(SpeechSettings.readAloud, on);
    if (!on) unawaited(speech.stop());
  }

  void _onCue() {
    final cue = source.cue;
    if (!enabled || identical(cue, _last)) return;
    _last = cue;
    if (cue == null) return;
    if (source.controller.state.status != PlaybackStatus.playing) return;
    final text = cue.plainText.replaceAll('\n', ' ').trim();
    if (text.isEmpty) return;
    unawaited(_say(text));
  }

  Future<void> _say(String text) async {
    try {
      await speech.stop();
      await speech.speak(
        text,
        languageTag: source.language,
        rate: settings.get(SpeechSettings.rate),
      );
    } on PlatformCapabilityUnavailable {
      // No voice on this device.
    }
  }

  void dispose() {
    source.removeListener(_onCue);
    unawaited(speech.stop());
  }
}
