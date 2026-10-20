import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/video/player/sleep_timer.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Current sleep-timer state for labels: "Off", "Pauses in 12:30", "End of
/// this video".
String sleepLabel(AppLocalizations l, SleepTimer t, Duration? reference) =>
    switch (t.setting) {
      SleepOff() => l.videoSleepOff,
      SleepAfterTime() => l.videoSleepRemaining(
        formatMediaDuration(t.remaining ?? Duration.zero),
      ),
      SleepAtEndOfItem() => l.videoSleepEndOfItem,
      SleepAtEndOfQueue() => l.videoSleepEndOfQueue,
    };

/// Sleep timer choices (VID-069).
Future<void> showSleepSheet(BuildContext context, SleepTimer t) {
  final l = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l.videoSleepTitle,
    builder: (sheetContext) {
      final current = t.setting;
      Widget option(String label, SleepSetting s, {required bool selected}) =>
          ListTile(
            title: Text(label),
            selected: selected,
            trailing: selected ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              t.set(s);
              Navigator.of(sheetContext).pop();
            },
          );
      return Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(
              l.videoSleepOff,
              const SleepOff(),
              selected: current is SleepOff,
            ),
            for (final d in SleepTimer.presets)
              option(
                l.videoSleepMinutes(d.inMinutes),
                SleepAfterTime(d),
                selected: current is SleepAfterTime && current.duration == d,
              ),
            option(
              l.videoSleepEndOfItem,
              const SleepAtEndOfItem(),
              selected: current is SleepAtEndOfItem,
            ),
            option(
              l.videoSleepEndOfQueue,
              const SleepAtEndOfQueue(),
              selected: current is SleepAtEndOfQueue,
            ),
          ],
        ),
      );
    },
  );
}

/// Volume 0–300 % and mute (VID-066). Above 100 % the engine boosts with a
/// limiter, so loud passages don't clip.
class VolumeRow extends StatelessWidget {
  const VolumeRow(this.c, {super.key});

  final VideoPlayerController c;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = c.volume.clamp(0.0, 3.0);
    final muted = c.state.muted;
    String percent(double x) => l.videoVolumeValue((x * 100).round());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: muted ? l.videoUnmute : l.videoMute,
              isSelected: muted,
              icon: const Icon(Icons.volume_up_rounded),
              selectedIcon: const Icon(Icons.volume_off_rounded),
              onPressed: () => unawaited(c.toggleMute()),
            ),
            Expanded(
              child: Slider(
                value: v,
                max: 3,
                divisions: 60,
                label: percent(v),
                semanticFormatterCallback: percent,
                onChanged: (x) => unawaited(c.setVolume(x)),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(percent(v), textAlign: TextAlign.end),
            ),
          ],
        ),
        if (v > 1)
          Text(
            l.videoVolumeBoostHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
