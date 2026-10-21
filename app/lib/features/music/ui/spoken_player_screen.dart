import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/book_player_screen.dart'
    show showSpeedSheet;
import 'package:mediahro/features/music/ui/extras.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// A chapter of a spoken-word item.
@immutable
final class SpokenChapter {
  const SpokenChapter(this.start, this.title);

  final Duration start;
  final String title;
}

/// What the spoken-word player screen shows (podcast episodes,
/// Audiobookshelf items).
@immutable
final class SpokenView {
  const SpokenView({
    required this.title,
    required this.subtitle,
    required this.position,
    required this.duration,
    required this.speed,
    required this.skipSilence,
    required this.playing,
    this.artPath,
    this.offline = false,
    this.chapters = const [],
  });

  final String title;
  final String subtitle;
  final String? artPath;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool skipSilence;
  final bool playing;

  /// Playing the downloaded copy.
  final bool offline;
  final List<SpokenChapter> chapters;

  int get chapterIndex {
    var i = -1;
    for (final (n, c) in chapters.indexed) {
      if (c.start <= position) i = n;
    }
    return i;
  }
}

/// What the screen's buttons do.
@immutable
final class SpokenControls {
  const SpokenControls({
    required this.toggle,
    required this.seek,
    required this.setSpeed,
    required this.setSkipSilence,
    required this.speed,
    required this.speedNote,
    this.markPlayed,
    this.showNotes,
    this.back = const Duration(seconds: 10),
    this.forward = const Duration(seconds: 30),
  });

  final VoidCallback toggle;
  final void Function(Duration position) seek;
  final void Function(double speed) setSpeed;
  final void Function({required bool enabled}) setSkipSilence;

  /// The speed, for the speed sheet to follow while it is open.
  final ProviderListenable<double> speed;
  final String Function(AppLocalizations l10n) speedNote;
  final VoidCallback? markPlayed;
  final VoidCallback? showNotes;
  final Duration back;
  final Duration forward;
}

/// The player while spoken word plays (POD-002, POD-003): artwork, title,
/// position and time left at the current speed, back and forward buttons,
/// chapters when there are some, speed and skip silence, sleep timer.
class SpokenPlayerScreen extends ConsumerStatefulWidget {
  const SpokenPlayerScreen({
    required this.title,
    required this.view,
    required this.controls,
    super.key,
  });

  /// The app bar title ("Podcast", "Audiobookshelf").
  final String title;
  final SpokenView view;
  final SpokenControls controls;

  @override
  ConsumerState<SpokenPlayerScreen> createState() => _SpokenPlayerScreenState();
}

class _SpokenPlayerScreenState extends ConsumerState<SpokenPlayerScreen> {
  /// Where the slider is while dragged, so the position doesn't jump back
  /// before the seek lands.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final v = widget.view;
    final c = widget.controls;
    final total = v.duration.inMilliseconds;
    final value = _drag ?? v.position.inMilliseconds.toDouble();
    final shown = Duration(milliseconds: value.round());
    final sleeping = ref.watch(sleepTimerStateProvider).value?.active ?? false;
    final index = v.chapterIndex;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.musicClose,
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.title),
        actions: [
          if (v.chapters.isNotEmpty)
            IconButton(
              tooltip: l10n.musicBookChapters,
              icon: const Icon(Icons.list),
              onPressed: () => _chapters(context, v),
            ),
          if (c.showNotes != null)
            IconButton(
              tooltip: l10n.musicPodShowNotes,
              icon: const Icon(Icons.notes),
              onPressed: c.showNotes,
            ),
          IconButton(
            tooltip: l10n.musicSleepTimer,
            isSelected: sleeping,
            icon: const Icon(Icons.bedtime_outlined),
            selectedIcon: Icon(Icons.bedtime, color: theme.colorScheme.primary),
            onPressed: () => showSleepSheet(context),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: KSpacing.s16),
                ShowArt(
                  path: v.artPath,
                  size: (box.maxHeight * 0.4).clamp(120, 280),
                ),
                const SizedBox(height: KSpacing.s16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    v.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Text(
                  v.subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (index >= 0)
                  Text(
                    v.chapters[index].title.isEmpty
                        ? l10n.musicBookChapterUnnamed(index + 1)
                        : v.chapters[index].title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                if (v.offline)
                  Text(l10n.musicPodOffline, style: theme.textTheme.bodySmall),
                const SizedBox(height: KSpacing.s16),
                Semantics(
                  label: l10n.musicBookPosition,
                  value: formatDuration(shown),
                  child: Slider(
                    max: total <= 0 ? 1 : total.toDouble(),
                    value: value.clamp(0, total <= 0 ? 1 : total.toDouble()),
                    onChanged: total <= 0
                        ? null
                        : (x) => setState(() => _drag = x),
                    onChangeEnd: (x) {
                      setState(() => _drag = null);
                      c.seek(Duration(milliseconds: x.round()));
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(shown)),
                    if (total > 0)
                      Text(
                        l10n.musicBookLeft(
                          formatDuration(
                            Duration(
                              microseconds:
                                  ((v.duration - shown).inMicroseconds /
                                          v.speed)
                                      .round()
                                      .clamp(0, 1 << 62),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: KSpacing.s8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (v.chapters.isNotEmpty)
                      IconButton(
                        tooltip: l10n.musicBookPreviousChapter,
                        iconSize: 32,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () => c.seek(_previousChapter(v)),
                      ),
                    IconButton(
                      tooltip: l10n.musicSpokenBack(c.back.inSeconds),
                      iconSize: 36,
                      icon: Icon(_replayIcon(c.back)),
                      onPressed: () => c.seek(v.position - c.back),
                    ),
                    IconButton.filled(
                      tooltip: v.playing
                          ? l10n.musicPauseLabel
                          : l10n.musicPlayLabel,
                      iconSize: 44,
                      icon: Icon(v.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: c.toggle,
                    ),
                    IconButton(
                      tooltip: l10n.musicSpokenForward(c.forward.inSeconds),
                      iconSize: 36,
                      icon: Icon(_forwardIcon(c.forward)),
                      onPressed: () => c.seek(v.position + c.forward),
                    ),
                    if (v.chapters.isNotEmpty)
                      IconButton(
                        tooltip: l10n.musicBookNextChapter,
                        iconSize: 32,
                        icon: const Icon(Icons.skip_next),
                        onPressed: index + 1 < v.chapters.length
                            ? () => c.seek(v.chapters[index + 1].start)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: KSpacing.s8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: KSpacing.s8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.speed, size: 18),
                      label: Text(l10n.musicBookSpeedValue(v.speed)),
                      tooltip: l10n.musicBookSpeed,
                      onPressed: () => showSpeedSheet(
                        context,
                        speed: c.speed,
                        onChange: (_, s) => c.setSpeed(s),
                        note: c.speedNote,
                      ),
                    ),
                    FilterChip(
                      label: Text(l10n.musicBookSkipSilence),
                      selected: v.skipSilence,
                      onSelected: (on) => c.setSkipSilence(enabled: on),
                    ),
                    if (c.markPlayed != null)
                      ActionChip(
                        avatar: const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                        ),
                        label: Text(l10n.musicPodMarkPlayed),
                        onPressed: c.markPlayed,
                      ),
                  ],
                ),
                const SizedBox(height: KSpacing.s24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Restarts the chapter after a few seconds into it, else the one before.
  Duration _previousChapter(SpokenView v) {
    final i = v.chapterIndex;
    if (i < 0) return Duration.zero;
    final into = v.position - v.chapters[i].start;
    final threshold = Duration(microseconds: (3000000 * v.speed).round());
    return into > threshold || i == 0
        ? v.chapters[i].start
        : v.chapters[i - 1].start;
  }

  void _chapters(BuildContext context, SpokenView v) => unawaited(
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
              child: Text(
                AppLocalizations.of(sheet).musicBookChapters,
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: v.chapters.length,
                itemBuilder: (_, i) {
                  final ch = v.chapters[i];
                  return ListTile(
                    selected: i == v.chapterIndex,
                    leading: Text(
                      AppLocalizations.of(sheet).musicBookNumber(i + 1),
                    ),
                    title: Text(
                      ch.title.isEmpty
                          ? AppLocalizations.of(sheet)
                                .musicBookChapterUnnamed(i + 1)
                          : ch.title,
                    ),
                    trailing: Text(formatDuration(ch.start)),
                    onTap: () {
                      widget.controls.seek(ch.start);
                      Navigator.of(sheet).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static IconData _replayIcon(Duration d) => switch (d.inSeconds) {
    5 => Icons.replay_5,
    10 => Icons.replay_10,
    30 => Icons.replay_30,
    _ => Icons.replay,
  };

  static IconData _forwardIcon(Duration d) => switch (d.inSeconds) {
    10 => Icons.forward_10,
    30 => Icons.forward_30,
    _ => Icons.fast_forward,
  };
}
