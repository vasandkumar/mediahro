import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/incoming/incoming_target.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/platform/platform_facades.dart' show storageProvider;
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// What other apps hand to Music (CORE-003, SYS-003, SYS-004): an audio file
/// from Open with or Share, and a playlist by name from an App Action.
///
/// The file plays as a transient item: it does not enter the library or the
/// saved queue, the queue keeps its place, and the music player shows it like
/// an episode (its own place, no library actions).
final class MusicIncoming {
  MusicIncoming({
    required this.player,
    required this.playlists,
    required this.open,
    required this.fileRoots,
  });

  final MusicPlayer player;
  final MusicPlaylists playlists;

  /// The `file:` folders the app already holds access to.
  final Future<List<Uri>> Function() fileRoots;

  /// The engine source for an address that mpv does not read itself (a
  /// `content:` URI, a share); throws [VirtualFileException] when nothing
  /// serves it.
  final Future<VirtualFile> Function(Uri uri) open;

  VirtualFile? _held;

  /// Plays the audio file at [uri]; false when it cannot be opened here (the
  /// video player, which plays audio too, then gets it).
  Future<bool> playExternalAudio(Uri uri) async {
    // What the hand-over may be: content from another app (never this app's
    // own) or a file in a folder the app holds. Anything else, web links
    // included, is refused before it can reach a source the listener added
    // (and be read with its credentials); the video player gets it and
    // checks it like any link.
    final target = classifyIncoming(uri, fileRoots: await fileRoots());
    if (target is! IncomingDocument) return false;
    final MediaSource source;
    VirtualFile? file;
    final title = titleOf(uri);
    if (uri.scheme == 'file') {
      source = UriSource(uri, title: title);
    } else {
      try {
        file = await open(uri);
      } on VirtualFileException {
        return false;
      }
      source = VirtualFileSource(file, title: title);
    }
    try {
      await player.playEpisode(
        NowPlayingEpisode(id: 'external:$uri', title: title, show: ''),
        source,
      );
      // A speed left over from a podcast is not this file's.
      await player.engine.setRate(1);
    } on Object {
      await file?.close();
      return false;
    }
    final old = _held;
    _held = file;
    if (old != null) await old.close();
    return true;
  }

  /// Starts the playlist called exactly [name] (any case); false when there
  /// is none or it has no songs the listener may see (hidden and locked ones
  /// never play from a spoken or shortcut request).
  Future<bool> playPlaylistByName(String name) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return false;
    final match = (await playlists.all())
        .where((p) => p.name.toLowerCase() == wanted)
        .firstOrNull;
    if (match == null) return false;
    final tracks = await playlists.tracks(match.id);
    if (tracks.isEmpty) return false;
    await player.playTracks(tracks);
    return true;
  }

  /// A readable title for a file address: its last segment, decoded, without
  /// the extension.
  static String titleOf(Uri uri) {
    var name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    // A `content:` document id may be `primary:Music/Song.mp3`.
    final colon = name.lastIndexOf(':');
    if (colon >= 0) name = name.substring(colon + 1);
    final slash = name.lastIndexOf('/');
    if (slash >= 0) name = name.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name.isEmpty ? (uri.host.isEmpty ? uri.toString() : uri.host) : name;
  }
}

/// Music's side of the incoming seams (C4a defines the providers in
/// `app/incoming/incoming_seams.dart`).
final musicIncomingProvider = Provider<MusicIncoming>((ref) {
  return MusicIncoming(
    player: ref.watch(musicPlayerProvider),
    playlists: ref.watch(musicPlaylistsProvider),
    open: (uri) => ref.read(mountsProvider).forUri(uri).open(uri),
    fileRoots: () async {
      try {
        final grants = await ref.read(storageProvider).grants();
        return [for (final g in grants) g.uri];
      } on Object {
        return const [];
      }
    },
  );
});
