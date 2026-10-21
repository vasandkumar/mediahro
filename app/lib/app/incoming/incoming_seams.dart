import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plays an audio file handed over by another app in the music player and
/// returns true; false (or no seam) leaves it to the video player, which plays
/// audio too. Music (C2) provides this.
typedef PlayExternalAudio = Future<bool> Function(Uri uri);

/// Starts the playlist called [name] in Music and returns true; false (or no
/// seam) means it could not. Music (C2) provides this.
typedef PlayPlaylistByName = Future<bool> Function(String name);

final playExternalAudioProvider = Provider<PlayExternalAudio?>((ref) => null);

final playPlaylistByNameProvider = Provider<PlayPlaylistByName?>((ref) => null);
