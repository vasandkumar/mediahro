import 'dart:convert';
import 'dart:io';

import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/lyrics/lrc.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

/// Finds lyrics for a song (MUS-005), in this order:
/// 1. lyrics the user edited or created (app cache),
/// 2. a sidecar `<song>.lrc` or `<song>.txt` next to the file,
/// 3. embedded lyrics (ID3 SYLT/USLT, Vorbis/APE/MP4 LYRICS),
/// 4. LRCLIB, only when the user turned that endpoint on (PRIV-004), cached.
final class LyricsService {
  LyricsService({
    required this.files,
    required this.cacheDir,
    required this.readTags,
    this.transport,
    this.onlineEnabled,
  });

  final MusicFiles files;

  /// `<app data>/music/lyrics`.
  final Directory cacheDir;

  /// Tag reader for the embedded lyrics (MUS-002).
  final Future<AudioTags> Function(VirtualFile file) readTags;

  /// [NetworkGateway] in the app; null disables online lookup.
  final HttpTransport? transport;

  /// Whether the LRCLIB endpoint is switched on.
  final bool Function()? onlineEnabled;

  static const int maxBytes = 1024 * 1024;

  Future<Lyrics?> forTrack(MusicTrack t, {bool allowOnline = true}) async {
    final edited = await _cached(t.itemId, 'lrc', LyricsOrigin.edited);
    if (edited != null) return edited;
    final sidecar = await _sidecar(t);
    if (sidecar != null) return sidecar;
    final embedded = await _embedded(t);
    if (embedded != null) return embedded;
    final online = await _cached(t.itemId, 'online.lrc', LyricsOrigin.online);
    if (online != null) return online;
    if (allowOnline && (onlineEnabled?.call() ?? false)) {
      return await lookupOnline(t);
    }
    return null;
  }

  /// Saves edited lyrics; they win over every other source afterwards.
  Future<void> saveEdited(MusicTrack t, Lyrics lyrics) async {
    await cacheDir.create(recursive: true);
    final f = _cacheFile(t.itemId, 'lrc');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(toLrc(lyrics), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> deleteEdited(MusicTrack t) async {
    final f = _cacheFile(t.itemId, 'lrc');
    if (f.existsSync()) await f.delete();
  }

  /// LRCLIB lookup (https://lrclib.net/docs): exact match by title, artist,
  /// album and duration, then a search. Throws [NetworkBlocked] when the
  /// endpoint is off.
  Future<Lyrics?> lookupOnline(MusicTrack t) async {
    final http = transport;
    final artist = t.artist ?? t.albumArtist;
    if (http == null || artist == null) return null;
    final params = {
      'track_name': t.title,
      'artist_name': artist,
      if (t.album != null) 'album_name': t.album!,
      if (t.duration != null) 'duration': '${t.duration!.inSeconds}',
    };
    var res = await http.send(
      HttpRequestData(
        method: 'GET',
        uri: Uri.https('lrclib.net', '/api/get', params),
        headers: const {'accept': 'application/json'},
      ),
    );
    Map<String, Object?>? hit;
    if (res.statusCode == 200) {
      hit = _jsonMap(res.body);
    } else if (res.statusCode == 404) {
      res = await http.send(
        HttpRequestData(
          method: 'GET',
          uri: Uri.https('lrclib.net', '/api/search', {
            'track_name': t.title,
            'artist_name': artist,
          }),
          headers: const {'accept': 'application/json'},
        ),
      );
      if (res.statusCode == 200) {
        final list = _jsonList(res.body);
        hit = _best(list, t.duration);
      }
    }
    if (hit == null) return null;
    final synced = hit['syncedLyrics'];
    final plain = hit['plainLyrics'];
    final text = synced is String && synced.trim().isNotEmpty
        ? synced
        : plain is String && plain.trim().isNotEmpty
        ? plain
        : null;
    if (text == null) return null;
    final lyrics = parseLyrics(text, origin: LyricsOrigin.online);
    await cacheDir.create(recursive: true);
    await _cacheFile(t.itemId, 'online.lrc').writeAsString(text);
    return lyrics;
  }

  Map<String, Object?>? _best(List<Object?> list, Duration? d) {
    Map<String, Object?>? best;
    var bestScore = 1 << 30;
    for (final e in list.take(50)) {
      if (e is! Map<String, Object?>) continue;
      final dur = e['duration'];
      final score = d == null || dur is! num
          ? 1000
          : (dur - d.inSeconds).abs().round();
      final hasSynced = e['syncedLyrics'] is String;
      final s = score * 2 - (hasSynced ? 1 : 0);
      if (s < bestScore && score <= 5) {
        bestScore = s;
        best = e;
      }
    }
    return best;
  }

  Future<Lyrics?> _cached(int itemId, String ext, LyricsOrigin origin) async {
    final f = _cacheFile(itemId, ext);
    if (!f.existsSync()) return null;
    final l = parseLyrics(await f.readAsString(), origin: origin);
    return l.isEmpty ? null : l;
  }

  File _cacheFile(int itemId, String ext) =>
      File('${cacheDir.path}${Platform.pathSeparator}$itemId.$ext');

  Future<Lyrics?> _sidecar(MusicTrack t) async {
    final dot = t.relPath.lastIndexOf('.');
    final stem = dot > t.relPath.lastIndexOf('/')
        ? t.relPath.substring(0, dot)
        : t.relPath;
    for (final ext in const ['lrc', 'LRC', 'txt']) {
      final text = await _readText(t.sourceId, '$stem.$ext');
      if (text != null) {
        final l = parseLyrics(text, origin: LyricsOrigin.sidecar);
        if (!l.isEmpty) return l;
      }
    }
    return null;
  }

  Future<String?> _readText(int sourceId, String rel) async {
    VirtualFile? f;
    try {
      f = await files.open(sourceId, rel);
      final size = await f.length() ?? maxBytes;
      final bytes = await f.read(0, size.clamp(0, maxBytes));
      return _decode(bytes);
    } on Exception {
      return null;
    } finally {
      await f?.close();
    }
  }

  Future<Lyrics?> _embedded(MusicTrack t) async {
    AudioTags tags;
    VirtualFile? f;
    try {
      f = await files.open(t.sourceId, t.relPath);
      tags = await readTags(f);
    } on Exception {
      return null;
    } finally {
      await f?.close();
    }
    if (tags.syncedLyrics.isNotEmpty) {
      return Lyrics([
        for (final l in tags.syncedLyrics) LyricLine(l.text, time: l.time),
      ]);
    }
    final text = tags.lyrics;
    if (text == null || text.trim().isEmpty) return null;
    return parseLyrics(text);
  }

  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes).replaceFirst('﻿', '');
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static Map<String, Object?>? _jsonMap(List<int> body) {
    try {
      final j = jsonDecode(utf8.decode(body, allowMalformed: true));
      return j is Map<String, Object?> ? j : null;
    } on FormatException {
      return null;
    }
  }

  static List<Object?> _jsonList(List<int> body) {
    try {
      final j = jsonDecode(utf8.decode(body, allowMalformed: true));
      return j is List<Object?> ? j : const [];
    } on FormatException {
      return const [];
    }
  }
}

/// True when [e] means the user has not switched the endpoint on.
bool isEndpointOff(Object e) => e is NetworkBlocked;
