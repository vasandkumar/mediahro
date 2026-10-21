import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/podcasts/podcast_player.dart';
import 'package:mediahro/features/music/ui/podcast_screen.dart';
import 'package:mediahro/features/music/ui/spoken_player_screen.dart';

/// The player while a podcast episode is in play (POD-002): back 10 and
/// forward 30 seconds, speed and skip silence (remembered by the show),
/// sleep timer, show notes, and a mark as played.
class PodcastPlayerScreen extends ConsumerWidget {
  const PodcastPlayerScreen({required this.state, super.key});

  final PodcastPlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.read(podcastPlayerProvider);
    final show = state.show!;
    final episode = state.episode!;
    return SpokenPlayerScreen(
      title: l10n.musicPodNowPlaying,
      view: SpokenView(
        title: episode.title,
        subtitle: show.title,
        artPath: show.artPath,
        position: state.position,
        duration: state.duration,
        speed: state.speed,
        skipSilence: state.skipSilence,
        playing: state.playing,
        offline: state.offline,
      ),
      controls: SpokenControls(
        toggle: () => unawaited(player.togglePlayPause()),
        seek: (p) => unawaited(player.seek(p)),
        setSpeed: (s) => unawaited(player.setSpeed(s)),
        setSkipSilence: ({required enabled}) =>
            unawaited(player.setSkipSilence(enabled: enabled)),
        speed: podcastPlayerStateProvider.select((s) => s.value?.speed ?? 1),
        speedNote: (l10n) => l10n.musicPodSpeedRemembered,
        markPlayed: () => unawaited(player.markPlayed(played: true)),
        showNotes: () => showEpisodeNotes(context, episode),
      ),
    );
  }
}
