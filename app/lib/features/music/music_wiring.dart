import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro/ui/mini_player_slot.dart';

/// Overrides main.dart adds for the music feature: the shell's mini player
/// (B3 slot) shows the music player while it has a track (MUS-006). Reading
/// the player at start-up also restores the last queue (MUS-007).
final List<Override> musicOverrides = [
  miniPlayerSlotProvider.overrideWith((ref) {
    if (!ref.watch(musicLibraryAvailableProvider)) return null;
    final hasTrack = ref.watch(
      musicPlayerStateProvider.select(
        (s) => s.value?.current != null || s.value?.station != null,
      ),
    );
    return hasTrack ? musicMiniPlayerSlot : null;
  }),
];
