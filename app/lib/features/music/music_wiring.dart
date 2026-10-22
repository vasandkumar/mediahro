import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/app/incoming/incoming_seams.dart';
import 'package:mediahro/features/music/music_incoming.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro/ui/mini_player_slot.dart';

/// Overrides main.dart adds for the music feature: the shell's mini player
/// (B3 slot) shows the music player while it has a track (MUS-006). Reading
/// the player at start-up also restores the last queue (MUS-007).
final List<Override> musicOverrides = [
  // What other apps hand to Music (CORE-003, SYS-003, SYS-004); without the
  // library the seams stay unset and the video player gets the file.
  playExternalAudioProvider.overrideWith((ref) {
    if (!ref.watch(musicLibraryAvailableProvider)) return null;
    return (uri) => ref.read(musicIncomingProvider).playExternalAudio(uri);
  }),
  playPlaylistByNameProvider.overrideWith((ref) {
    if (!ref.watch(musicLibraryAvailableProvider)) return null;
    return (name) => ref.read(musicIncomingProvider).playPlaylistByName(name);
  }),
  miniPlayerSlotProvider.overrideWith((ref) {
    if (!ref.watch(musicLibraryAvailableProvider)) return null;
    // Starts the podcast refresh once the library is open.
    ref.watch(podcastBootProvider);
    final hasTrack = ref.watch(
      musicPlayerStateProvider.select(
        (s) =>
            s.value?.current != null ||
            s.value?.station != null ||
            s.value?.episode != null,
      ),
    );
    return hasTrack ? musicMiniPlayerSlot : null;
  }),
];
