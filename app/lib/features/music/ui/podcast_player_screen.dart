import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/podcasts/podcast_player.dart';
import 'package:mediahro/features/music/ui/book_player_screen.dart'
    show showSpeedSheet;
import 'package:mediahro/features/music/ui/extras.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/features/music/ui/podcast_screen.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The player while a podcast episode is in play (POD-002): artwork, show,
/// position and time left at the current speed, back 10 and forward 30
/// seconds, speed and skip silence (remembered by the show), sleep timer,
/// show notes, and a mark as played.
class PodcastPlayerScreen extends ConsumerStatefulWidget {
  const PodcastPlayerScreen({required this.state, super.key});

  final PodcastPlayerState state;

  @override
  ConsumerState<PodcastPlayerScreen> createState() =>
      _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends ConsumerState<PodcastPlayerScreen> {
  double? _drag;

  static const _back = Duration(seconds: 10);
  static const _forward = Duration(seconds: 30);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = widget.state;
    final show = s.show!;
    final episode = s.episode!;
    final player = ref.read(podcastPlayerProvider);
    final total = s.duration.inMilliseconds;
    final value = _drag ?? s.position.inMilliseconds.toDouble();
    final shown = Duration(milliseconds: value.round());
    final sleeping = ref.watch(sleepTimerStateProvider).value?.active ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.musicClose,
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.musicPodNowPlaying),
        actions: [
          IconButton(
            tooltip: l10n.musicPodShowNotes,
            icon: const Icon(Icons.notes),
            onPressed: () => showEpisodeNotes(context, episode),
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
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: KSpacing.s16),
                ShowArt(
                  path: show.artPath,
                  size: (c.maxHeight * 0.4).clamp(120, 280),
                ),
                const SizedBox(height: KSpacing.s16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    episode.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Text(
                  show.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (s.offline)
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
                        : (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      setState(() => _drag = null);
                      unawaited(player.seek(Duration(milliseconds: v.round())));
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
                                  ((s.duration - shown).inMicroseconds /
                                          s.speed)
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
                    IconButton(
                      tooltip: l10n.musicPodBack10,
                      iconSize: 36,
                      icon: const Icon(Icons.replay_10),
                      onPressed: () => unawaited(player.skip(-_back)),
                    ),
                    IconButton.filled(
                      tooltip: s.playing
                          ? l10n.musicPauseLabel
                          : l10n.musicPlayLabel,
                      iconSize: 44,
                      icon: Icon(s.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () => unawaited(player.togglePlayPause()),
                    ),
                    IconButton(
                      tooltip: l10n.musicPodForward30,
                      iconSize: 36,
                      icon: const Icon(Icons.forward_30),
                      onPressed: () => unawaited(player.skip(_forward)),
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
                      label: Text(l10n.musicBookSpeedValue(s.speed)),
                      tooltip: l10n.musicBookSpeed,
                      onPressed: () => showSpeedSheet(
                        context,
                        speedOf: (ref) => ref.watch(
                          podcastPlayerStateProvider.select(
                            (s) => s.value?.speed ?? 1,
                          ),
                        ),
                        onChange: (ref, v) => unawaited(
                          ref.read(podcastPlayerProvider).setSpeed(v),
                        ),
                        note: (l10n) => l10n.musicPodSpeedRemembered,
                      ),
                    ),
                    FilterChip(
                      label: Text(l10n.musicBookSkipSilence),
                      selected: s.skipSilence,
                      onSelected: (v) =>
                          unawaited(player.setSkipSilence(enabled: v)),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(l10n.musicPodMarkPlayed),
                      onPressed: () =>
                          unawaited(player.markPlayed(played: true)),
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
}
