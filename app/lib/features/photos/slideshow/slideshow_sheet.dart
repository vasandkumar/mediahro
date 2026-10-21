import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_music.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_options.dart';

/// "5×", "0.75×": a speed as people say it.
String slideshowSpeedText(BuildContext context, double speed) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final f = NumberFormat('0.##', locale);
  return f.format(speed);
}

/// The slideshow's choices as a sheet (IMG-012); every change is applied at
/// once through [onChanged]. Returns when the sheet is closed.
Future<void> showSlideshowSheet(
  BuildContext context,
  WidgetRef ref,
  SlideshowOptions current, {
  required ValueChanged<SlideshowOptions> onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _SlideshowSheet(
    initial: current,
    music: ref.read(slideshowMusicProvider),
    onChanged: onChanged,
  ),
);

class _SlideshowSheet extends StatefulWidget {
  const _SlideshowSheet({
    required this.initial,
    required this.music,
    required this.onChanged,
  });

  final SlideshowOptions initial;
  final SlideshowMusic music;
  final ValueChanged<SlideshowOptions> onChanged;

  @override
  State<_SlideshowSheet> createState() => _SlideshowSheetState();
}

class _SlideshowSheetState extends State<_SlideshowSheet> {
  late SlideshowOptions _o = widget.initial;
  List<SlideMusicPlaylist> _playlists = const [];

  @override
  void initState() {
    super.initState();
    if (widget.music.available) unawaited(_loadPlaylists());
  }

  Future<void> _loadPlaylists() async {
    final p = await widget.music.playlists();
    if (mounted) setState(() => _playlists = p);
  }

  void _set(SlideshowOptions next) {
    setState(() => _o = next);
    widget.onChanged(next);
  }

  String _transitionName(AppLocalizations l10n, SlideChange t) => switch (t) {
    SlideChange.none => l10n.photosSlideshowTransitionNone,
    SlideChange.fade => l10n.photosSlideshowTransitionFade,
    SlideChange.slide => l10n.photosSlideshowTransitionSlide,
    SlideChange.zoom => l10n.photosSlideshowTransitionZoom,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final seconds = _o.interval.round();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.photosSlideshowOptions,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.photosSlideshowInterval(seconds),
              style: theme.textTheme.titleSmall,
            ),
            Slider(
              value: _o.interval,
              min: SlideshowOptions.minInterval,
              max: SlideshowOptions.maxInterval,
              divisions:
                  (SlideshowOptions.maxInterval - SlideshowOptions.minInterval)
                      .round(),
              label: l10n.photosSlideshowInterval(seconds),
              semanticFormatterCallback: (v) =>
                  l10n.photosSlideshowInterval(v.round()),
              onChanged: (v) => _set(_o.copyWith(interval: v)),
            ),
            Text(
              l10n.photosSlideshowTransition,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final t in SlideChange.values)
                  ChoiceChip(
                    label: Text(_transitionName(l10n, t)),
                    selected: _o.transition == t,
                    onSelected: (_) => _set(_o.copyWith(transition: t)),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.photosSlideshowKenBurns),
              subtitle: Text(l10n.photosSlideshowKenBurnsHint),
              value: _o.kenBurns,
              onChanged: (v) => _set(_o.copyWith(kenBurns: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.photosSlideshowRandom),
              value: _o.random,
              onChanged: (v) => _set(_o.copyWith(random: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.photosSlideshowLoop),
              value: _o.loop,
              onChanged: (v) => _set(_o.copyWith(loop: v)),
            ),
            if (widget.music.available) ...[
              const SizedBox(height: 8),
              Text(
                l10n.photosSlideshowMusic,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l10n.photosSlideshowMusicNone),
                    selected: _o.music == SlideMusicSource.none,
                    onSelected: (_) =>
                        _set(_o.copyWith(music: SlideMusicSource.none)),
                  ),
                  ChoiceChip(
                    label: Text(l10n.photosSlideshowMusicLibrary),
                    selected: _o.music == SlideMusicSource.library,
                    onSelected: (_) =>
                        _set(_o.copyWith(music: SlideMusicSource.library)),
                  ),
                  if (_playlists.isNotEmpty)
                    ChoiceChip(
                      label: Text(l10n.photosSlideshowMusicPlaylist),
                      selected: _o.music == SlideMusicSource.playlist,
                      onSelected: (_) => _set(
                        _o.copyWith(
                          music: SlideMusicSource.playlist,
                          playlistId: _o.playlistId ?? _playlists.first.id,
                        ),
                      ),
                    ),
                ],
              ),
              if (_o.music == SlideMusicSource.playlist &&
                  _playlists.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _playlists.any((p) => p.id == _o.playlistId)
                        ? _o.playlistId
                        : _playlists.first.id,
                    items: [
                      for (final p in _playlists)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (id) {
                      if (id != null) _set(_o.copyWith(playlistId: id));
                    },
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.photosSlideshowDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
