import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Frame-rate conversions for subtitles (SUB-015): (from fps, to fps). The
/// factor is to / from, as mpv's `sub-speed` takes it.
const List<(double, double)> subtitleFpsConversions = [
  (23.976, 25),
  (25, 23.976),
  (24, 25),
  (25, 24),
  (23.976, 24),
  (24, 23.976),
  (29.97, 25),
  (25, 29.97),
];

double fpsFactor((double, double) c) => c.$2 / c.$1;

String _fps(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// "Normal" or "23.976 → 25 fps" for the current subtitle speed.
String subtitleSpeedLabel(AppLocalizations l, double speed) {
  if ((speed - 1).abs() < 1e-6) return l.videoSubSpeedNormal;
  for (final c in subtitleFpsConversions) {
    if ((fpsFactor(c) - speed).abs() < 1e-6) {
      return l.videoSubSpeedFps(_fps(c.$1), _fps(c.$2));
    }
  }
  return l.videoSpeedValue(speed);
}

/// Subtitle speed for frame-rate conversion (SUB-015).
Future<void> showSubtitleSpeedSheet(
  BuildContext context,
  VideoPlayerController c,
) {
  final l = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l.videoSubSpeedTitle,
    builder: (sheetContext) {
      final current = c.subtitleSpeed;
      Widget option(double speed) {
        final selected = (current - speed).abs() < 1e-6;
        return ListTile(
          title: Text(subtitleSpeedLabel(l, speed)),
          selected: selected,
          trailing: selected ? const Icon(Icons.check_rounded) : null,
          onTap: () {
            unawaited(c.setSubtitleSpeed(speed));
            Navigator.of(sheetContext).pop();
          },
        );
      }

      return Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(1),
            for (final conv in subtitleFpsConversions) option(fpsFactor(conv)),
          ],
        ),
      );
    },
  );
}

/// Second subtitles (SUB-016): another track at the same time, with its
/// own delay; its size and place are in Settings → Subtitles.
Future<void> showSecondarySubtitleSheet(
  BuildContext context,
  VideoPlayerController c, {
  required String Function(Track t, int index) label,
}) {
  final l = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l.videoSubSecondaryTitle,
    builder: (_) => ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final tracks = c.tracksOf(TrackType.subtitle);
        final delay = c.secondarySubtitleDelay;
        const step = Duration(milliseconds: 50);
        return Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<int>(
                groupValue: c.state.secondarySubtitleTrackId ?? -1,
                onChanged: (id) => unawaited(
                  c.selectSecondarySubtitle(
                    tracks.where((t) => t.id == id).firstOrNull,
                  ),
                ),
                child: Column(
                  children: [
                    RadioListTile<int>(
                      value: -1,
                      title: Text(l.videoSubtitlesOff),
                    ),
                    for (final (i, t) in tracks.indexed)
                      RadioListTile<int>(
                        value: t.id,
                        // The first subtitles can't be shown twice.
                        enabled: t.id != c.state.subtitleTrackId,
                        title: Text(label(t, i)),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text(l.videoSubSecondaryDelay)),
                  IconButton(
                    tooltip: l.videoDelayEarlier,
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: () =>
                        unawaited(c.setSecondarySubtitleDelay(delay - step)),
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(l.videoDelayValue(delay.inMilliseconds)),
                  ),
                  IconButton(
                    tooltip: l.videoDelayLater,
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () =>
                        unawaited(c.setSecondarySubtitleDelay(delay + step)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The second subtitle line, drawn by the player at its own size
/// (SUB-016, ADR-021): mpv only renders the first.
class SecondarySubtitleText extends StatelessWidget {
  const SecondarySubtitleText({
    required this.text,
    required this.scale,
    super.key,
  });

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.titleLarge!;
    const edge = [
      Shadow(blurRadius: 3),
      Shadow(offset: Offset(1, 1), blurRadius: 2),
    ];
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: base.copyWith(
          color: Colors.white,
          fontSize: (base.fontSize ?? 22) * scale,
          shadows: edge,
        ),
      ),
    );
  }
}
