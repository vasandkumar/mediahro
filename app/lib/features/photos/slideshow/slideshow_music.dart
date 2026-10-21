import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_options.dart';

/// A playlist the slideshow can play.
typedef SlideMusicPlaylist = ({int id, String name, int count});

/// The music of a slideshow, from the Music library (IMG-012). Faked in
/// widget tests.
abstract interface class SlideshowMusic {
  /// Whether there is a music library to play from.
  bool get available;

  /// The playlists to choose from.
  Future<List<SlideMusicPlaylist>> playlists();

  /// Starts the music [options] asks for; false when there is nothing to
  /// play (an empty library or playlist).
  Future<bool> start(SlideshowOptions options);

  /// Pauses what [start] began.
  Future<void> stop();
}

/// No music library (shell builds and tests without a database).
final class NoSlideshowMusic implements SlideshowMusic {
  const NoSlideshowMusic();

  @override
  bool get available => false;

  @override
  Future<List<SlideMusicPlaylist>> playlists() async => const [];

  @override
  Future<bool> start(SlideshowOptions options) async => false;

  @override
  Future<void> stop() async {}
}

/// Plays through the music player: the whole library shuffled, or a
/// playlist in its order.
final class LibrarySlideshowMusic implements SlideshowMusic {
  LibrarySlideshowMusic({
    required this.player,
    required this.library,
    required this.playlistsOf,
  });

  final MusicPlayer player;
  final MusicLibrary library;
  final MusicPlaylists playlistsOf;
  bool _started = false;

  @override
  bool get available => true;

  @override
  Future<List<SlideMusicPlaylist>> playlists() async => [
    for (final p in await playlistsOf.all())
      if (p.count > 0) (id: p.id, name: p.name, count: p.count),
  ];

  @override
  Future<bool> start(SlideshowOptions options) async {
    final List<MusicTrack> tracks;
    switch (options.music) {
      case SlideMusicSource.none:
        return false;
      case SlideMusicSource.library:
        tracks = await library.songs();
      case SlideMusicSource.playlist:
        final id = options.playlistId;
        if (id == null) return false;
        tracks = await playlistsOf.tracks(id);
    }
    if (tracks.isEmpty) return false;
    await player.playTracks(
      tracks,
      shuffle: options.music == SlideMusicSource.library,
    );
    _started = true;
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await player.pause();
  }
}

final slideshowMusicProvider = Provider<SlideshowMusic>((ref) {
  if (!ref.watch(musicLibraryAvailableProvider)) {
    return const NoSlideshowMusic();
  }
  return LibrarySlideshowMusic(
    player: ref.watch(musicPlayerProvider),
    library: ref.watch(musicLibraryProvider),
    playlistsOf: ref.watch(musicPlaylistsProvider),
  );
});
