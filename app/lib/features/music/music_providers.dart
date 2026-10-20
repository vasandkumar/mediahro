import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, ProviderException;
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_indexer.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_session.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Whether the app runs with a library database (always in the app; shell
/// tests run without one).
final musicLibraryAvailableProvider = Provider<bool>((ref) {
  try {
    ref.watch(libraryDatabaseProvider);
    return true;
  } on Object {
    return false;
  }
});

final musicLibraryProvider = Provider<MusicLibrary>(
  (ref) => MusicLibrary(ref.watch(libraryDatabaseProvider)),
);

final musicFilesProvider = Provider<MusicFiles>((ref) {
  final f = MusicFiles(
    ref.watch(libraryDatabaseProvider),
    ref.watch(sourceResolverProvider),
  );
  ref.onDispose(() => unawaited(f.close()));
  return f;
});

final artworkStoreProvider = Provider<ArtworkStore>(
  (ref) => ArtworkStore(
    ref.watch(libraryDatabaseProvider),
    Directory(
      [
        ref.watch(appDataDirectoryProvider).path,
        'music',
        'art',
      ].join(Platform.pathSeparator),
    ),
  ),
);

/// Background tag and art reading (MUS-002, MUS-004); started by the music
/// screen and kept for the app's life.
final musicIndexerProvider = Provider<MusicIndexer>((ref) {
  final i = MusicIndexer(
    db: ref.watch(libraryDatabaseProvider),
    files: ref.watch(musicFilesProvider),
    art: ref.watch(artworkStoreProvider),
  )..start();
  ref.onDispose(() => unawaited(i.dispose()));
  return i;
});

/// The music player over the pool's music engine (MUS-006, MUS-007).
final musicPlayerProvider = Provider<MusicPlayer>((ref) {
  final p = MusicPlayer(
    engine: ref.watch(playbackEngineProvider(EngineRole.music)),
    queues: ref.watch(queueRepositoryProvider),
    library: ref.watch(musicLibraryProvider),
    files: ref.watch(musicFilesProvider),
    progress: ref.watch(progressRepositoryProvider),
    playlists: ref.watch(playlistRepositoryProvider),
  );
  unawaited(p.init());
  ref.onDispose(() => unawaited(p.dispose()));
  final session = _optional(() => ref.watch(mediaSessionProvider));
  if (session != null) {
    final bridge = MusicSessionBridge(
      player: p,
      session: session,
      art: ref.watch(artworkStoreProvider),
      widgets: _optional(() => ref.watch(homeWidgetsProvider)),
    )..start();
    ref.onDispose(() => unawaited(bridge.dispose()));
  }
  return p;
});

final musicPlayerStateProvider = StreamProvider<MusicPlayerState>(
  (ref) => ref.watch(musicPlayerProvider).states,
);

/// Bumps whenever music items, tags or art change, so views reload.
final musicLibraryChangesProvider = StreamProvider<int>((ref) async* {
  var n = 0;
  yield n;
  await for (final _ in ref.watch(musicLibraryProvider).changes()) {
    yield ++n;
  }
});

/// Cover file of an item (MUS-004), or null.
final FutureProviderFamily<String?, int> coverPathProvider =
    FutureProvider.family<String?, int>((ref, itemId) {
      ref.watch(musicLibraryChangesProvider);
      return ref.watch(artworkStoreProvider).coverPath(itemId);
    });

T? _optional<T>(T Function() read) {
  try {
    return read();
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
}
