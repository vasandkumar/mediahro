import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/visualizer/visualizer.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The visualiser in Now Playing (AUD-046): spectrum, waveform or level
/// meters drawn on the raster thread, coloured from the cover, with a
/// low-power mode. Taps the engine only while visible.
class VisualizerView extends ConsumerStatefulWidget {
  const VisualizerView({required this.track, super.key});

  final MusicTrack track;

  @override
  ConsumerState<VisualizerView> createState() => _VisualizerViewState();
}

class _VisualizerViewState extends ConsumerState<VisualizerView> {
  VisualizerController? _controller;
  VisualizerStyle _style = VisualizerStyle.spectrum;
  ColorScheme? _palette;
  String? _paletteFor;

  @override
  void initState() {
    super.initState();
    final feed = ref.read(visualizerFeedProvider);
    if (feed != null) _controller = VisualizerController(feed: feed)..start();
    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final m = await ref.read(musicPrefsProvider).readMap('visualizer');
    if (m == null || !mounted) return;
    setState(() {
      _style =
          VisualizerStyle.values
              .where((s) => s.name == m['style'])
              .firstOrNull ??
          _style;
      _controller?.lowPower = m['lowPower'] == true;
    });
  }

  void _save() => unawaited(
    ref.read(musicPrefsProvider).write('visualizer', {
      'style': _style.name,
      'lowPower': _controller?.lowPower ?? false,
    }),
  );

  Future<void> _paletteFrom(String? cover, Brightness b) async {
    if (cover == _paletteFor) return;
    _paletteFor = cover;
    if (cover == null) {
      setState(() => _palette = null);
      return;
    }
    try {
      final s = await ColorScheme.fromImageProvider(
        provider: ResizeImage(FileImage(File(cover)), width: 64, height: 64),
        brightness: b,
      );
      if (mounted) setState(() => _palette = s);
    } on Exception {
      // Keep the theme colours.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = _controller;
    final cover = ref.watch(coverPathProvider(widget.track.itemId)).value;
    unawaited(_paletteFrom(cover, theme.brightness));
    if (c == null) {
      return KEmptyState(message: l10n.musicVisualizerUnavailable);
    }
    final scheme = _palette ?? theme.colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<VisualizerStyle>(
                showSelectedIcon: false,
                segments: [
                  for (final s in VisualizerStyle.values)
                    ButtonSegment(
                      value: s,
                      label: Text(l10n.musicVisualizerStyle(s.name)),
                    ),
                ],
                selected: {_style},
                onSelectionChanged: (v) {
                  setState(() => _style = v.first);
                  _save();
                },
              ),
            ),
          ],
        ),
        Expanded(
          child: Semantics(
            label: l10n.musicVisualizerSemantics,
            image: true,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: VisualizerPainter(
                  controller: c,
                  style: _style,
                  primary: scheme.primary,
                  secondary: scheme.tertiary,
                  track: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.musicVisualizerLowPower),
          value: c.lowPower,
          onChanged: (v) {
            setState(() => c.lowPower = v);
            _save();
          },
        ),
      ],
    );
  }
}
