import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:meta/meta.dart';

enum PlaylistFormat { m3u, pls, xspf, cue }

/// Hard limits for untrusted playlists (PRIV-005).
const int maxPlaylistBytes = 4 << 20;
const int maxPlaylistEntries = 100000;

@immutable
final class PlaylistEntry {
  const PlaylistEntry(
    this.location, {
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.start,
    this.headers = const {},
  });

  /// Absolute URI string, or a path relative to the playlist when no base
  /// was given.
  final String location;
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;

  /// Track start inside [location] (CUE sheets).
  final Duration? start;

  /// Per-entry HTTP headers (`#EXTVLCOPT:http-user-agent`, NET-006).
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      other is PlaylistEntry &&
      other.location == location &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.duration == duration &&
      other.start == start &&
      other.headers.length == headers.length &&
      other.headers.entries.every((e) => headers[e.key] == e.value);

  @override
  int get hashCode =>
      Object.hash(location, title, artist, album, duration, start);

  @override
  String toString() => 'PlaylistEntry($location, $title, $duration, $start)';
}

@immutable
final class ParsedPlaylist {
  const ParsedPlaylist(this.entries, {this.title, this.isHlsStream = false});

  final List<PlaylistEntry> entries;
  final String? title;

  /// The `.m3u8` is an HLS media/master playlist: open it as one stream.
  final bool isHlsStream;
}

final class PlaylistFormatException extends FormatException {
  const PlaylistFormatException(super.message);
}

PlaylistFormat? playlistFormatFor(String fileName) =>
    switch (fileName.toLowerCase().split('.').last) {
      'm3u' || 'm3u8' => PlaylistFormat.m3u,
      'pls' => PlaylistFormat.pls,
      'xspf' => PlaylistFormat.xspf,
      'cue' => PlaylistFormat.cue,
      _ => null,
    };

/// Parses [bytes] on a separate isolate (PRIV-005: parsers never run on the
/// UI isolate and never see more than [maxPlaylistBytes]).
Future<ParsedPlaylist> parsePlaylistIsolated(
  Uint8List bytes,
  PlaylistFormat format, {
  Uri? base,
}) {
  if (bytes.length > maxPlaylistBytes) {
    throw const PlaylistFormatException('playlist too large');
  }
  return Isolate.run(
    () => parsePlaylist(decodeText(bytes), format, base: base),
  );
}

ParsedPlaylist parsePlaylist(String text, PlaylistFormat format, {Uri? base}) {
  if (text.length > maxPlaylistBytes) {
    throw const PlaylistFormatException('playlist too large');
  }
  return switch (format) {
    PlaylistFormat.m3u => parseM3u(text, base: base),
    PlaylistFormat.pls => parsePls(text, base: base),
    PlaylistFormat.xspf => parseXspf(text, base: base),
    PlaylistFormat.cue => parseCue(text, base: base),
  };
}

/// UTF-8 (BOM optional) when valid, else Windows-1252/Latin-1 (legacy
/// `.m3u`); UTF-16 by BOM.
String decodeText(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    return String.fromCharCodes(Uint16List.sublistView(_even(b, 2)));
  }
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final swapped = Uint8List(b.length - 2);
    for (var i = 2; i + 1 < b.length; i += 2) {
      swapped[i - 2] = b[i + 1];
      swapped[i - 1] = b[i];
    }
    return String.fromCharCodes(Uint16List.sublistView(_even(swapped, 0)));
  }
  final start = b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF
      ? 3
      : 0;
  try {
    return utf8.decode(Uint8List.sublistView(b, start));
  } on FormatException {
    return latin1.decode(b);
  }
}

Uint8List _even(Uint8List b, int from) {
  final n = (b.length - from) & ~1;
  return Uint8List.fromList(b.sublist(from, from + n));
}

String _resolve(String loc, Uri? base) {
  final l = loc.trim();
  if (base == null) return l;
  if (RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(l)) return l;
  try {
    // Windows absolute paths in playlists made on Windows.
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(l)) {
      return Uri.file(l, windows: true).toString();
    }
    final rel = l.replaceAll(r'\', '/');
    if (rel.startsWith('/') && base.scheme == 'file') {
      return Uri.file(rel, windows: false).toString();
    }
    return base.resolveUri(Uri(path: rel)).toString();
    // Uri.file reports characters no URI can hold as ArgumentError: keep the
    // raw text and let the opener report it.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return l;
  } on FormatException {
    return l;
  }
}

void _checkCount(int n) {
  if (n >= maxPlaylistEntries) {
    throw const PlaylistFormatException('too many entries');
  }
}

ParsedPlaylist parseM3u(String text, {Uri? base}) {
  final lines = const LineSplitter().convert(text);
  if (lines.any(
    (l) =>
        l.startsWith('#EXT-X-TARGETDURATION') ||
        l.startsWith('#EXT-X-STREAM-INF') ||
        l.startsWith('#EXT-X-MEDIA-SEQUENCE'),
  )) {
    return const ParsedPlaylist([], isHlsStream: true);
  }
  final out = <PlaylistEntry>[];
  String? title;
  String? artist;
  Duration? duration;
  String? listTitle;
  var headers = <String, String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF:')) {
      final body = line.substring(8);
      final comma = _unquotedComma(body);
      final durStr = (comma < 0 ? body : body.substring(0, comma))
          .split(' ')
          .first;
      final secs = double.tryParse(durStr);
      duration = secs == null || secs < 0
          ? null
          : Duration(milliseconds: (secs * 1000).round());
      final t = comma < 0 ? '' : body.substring(comma + 1).trim();
      final dash = t.indexOf(' - ');
      if (dash > 0) {
        artist = t.substring(0, dash).trim();
        title = t.substring(dash + 3).trim();
      } else {
        title = t.isEmpty ? null : t;
        artist = null;
      }
    } else if (line.startsWith('#PLAYLIST:')) {
      listTitle = line.substring(10).trim();
    } else if (line.startsWith('#EXTVLCOPT:')) {
      final opt = line.substring(11);
      final eq = opt.indexOf('=');
      if (eq > 0) {
        final key = opt.substring(0, eq).trim().toLowerCase();
        final value = opt.substring(eq + 1).trim();
        if (key == 'http-user-agent') headers['User-Agent'] = value;
        if (key == 'http-referrer' || key == 'http-referer') {
          headers['Referer'] = value;
        }
      }
    } else if (line.startsWith('#')) {
      continue;
    } else {
      _checkCount(out.length);
      out.add(
        PlaylistEntry(
          _resolve(line, base),
          title: title,
          artist: artist,
          duration: duration,
          headers: headers,
        ),
      );
      title = null;
      artist = null;
      duration = null;
      headers = <String, String>{};
    }
  }
  return ParsedPlaylist(out, title: listTitle);
}

int _unquotedComma(String s) {
  var inQuote = false;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '"') inQuote = !inQuote;
    if (s[i] == ',' && !inQuote) return i;
  }
  return -1;
}

ParsedPlaylist parsePls(String text, {Uri? base}) {
  final files = <int, String>{};
  final titles = <int, String>{};
  final lengths = <int, int>{};
  final key = RegExp(r'^(File|Title|Length)(\d+)$', caseSensitive: false);
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final m = key.firstMatch(line.substring(0, eq).trim());
    if (m == null) continue;
    final n = int.parse(m.group(2)!);
    if (n > maxPlaylistEntries) {
      throw const PlaylistFormatException('too many entries');
    }
    final v = line.substring(eq + 1).trim();
    switch (m.group(1)!.toLowerCase()) {
      case 'file':
        files[n] = v;
      case 'title':
        titles[n] = v;
      case 'length':
        lengths[n] = int.tryParse(v) ?? -1;
    }
  }
  final keys = files.keys.toList()..sort();
  return ParsedPlaylist([
    for (final n in keys)
      PlaylistEntry(
        _resolve(files[n]!, base),
        title: titles[n],
        duration: (lengths[n] ?? -1) < 0
            ? null
            : Duration(seconds: lengths[n]!),
      ),
  ]);
}

ParsedPlaylist parseXspf(String text, {Uri? base}) {
  final XmlElement root;
  try {
    root = parseXml(
      text,
      limits: const XmlLimits(
        maxLength: maxPlaylistBytes,
        maxNodes: maxPlaylistEntries * 8,
      ),
    );
  } on XmlFormatException catch (e) {
    throw PlaylistFormatException('invalid XSPF: ${e.message}');
  }
  if (root.localName != 'playlist') {
    throw const PlaylistFormatException('not an XSPF playlist');
  }
  final out = <PlaylistEntry>[];
  for (final track
      in root.child('trackList')?.all('track') ?? const <XmlElement>[]) {
    final loc = track.childText('location');
    if (loc == null || loc.isEmpty) continue;
    _checkCount(out.length);
    final ms = int.tryParse(track.childText('duration') ?? '');
    out.add(
      PlaylistEntry(
        _resolve(loc, base),
        title: track.childText('title'),
        artist: track.childText('creator'),
        album: track.childText('album'),
        duration: ms == null ? null : Duration(milliseconds: ms),
      ),
    );
  }
  return ParsedPlaylist(out, title: root.childText('title'));
}

/// CUE sheet: one entry per TRACK with its start (INDEX 01) inside FILE.
ParsedPlaylist parseCue(String text, {Uri? base}) {
  final out = <PlaylistEntry>[];
  String? file;
  String? albumTitle;
  String? albumPerformer;
  String? title;
  String? performer;
  var inTrack = false;
  Duration? start;
  void flush() {
    if (inTrack && file != null && start != null) {
      _checkCount(out.length);
      out.add(
        PlaylistEntry(
          _resolve(file, base),
          title: title,
          artist: performer ?? albumPerformer,
          album: albumTitle,
          start: start,
        ),
      );
    }
  }

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final sp = line.indexOf(' ');
    if (sp < 0) continue;
    final cmd = line.substring(0, sp).toUpperCase();
    final arg = line.substring(sp + 1).trim();
    switch (cmd) {
      case 'FILE':
        flush();
        inTrack = false;
        file = _quoted(arg);
      case 'TRACK':
        flush();
        inTrack = true;
        title = null;
        performer = null;
        start = null;
      case 'TITLE':
        if (inTrack) {
          title = _quoted(arg);
        } else {
          albumTitle = _quoted(arg);
        }
      case 'PERFORMER':
        if (inTrack) {
          performer = _quoted(arg);
        } else {
          albumPerformer = _quoted(arg);
        }
      case 'INDEX':
        final parts = arg.split(RegExp(r'\s+'));
        if (parts.length == 2 && int.tryParse(parts[0]) == 1) {
          start = _cueTime(parts[1]);
        }
    }
  }
  flush();
  // Durations follow from the next track's start in the same file.
  final withDur = <PlaylistEntry>[];
  for (var i = 0; i < out.length; i++) {
    final e = out[i];
    final next = i + 1 < out.length ? out[i + 1] : null;
    withDur.add(
      PlaylistEntry(
        e.location,
        title: e.title,
        artist: e.artist,
        album: e.album,
        start: e.start,
        duration: next != null && next.location == e.location
            ? next.start! - e.start!
            : null,
      ),
    );
  }
  return ParsedPlaylist(withDur, title: albumTitle);
}

String _quoted(String arg) {
  if (arg.startsWith('"')) {
    final end = arg.indexOf('"', 1);
    return end < 0 ? arg.substring(1) : arg.substring(1, end);
  }
  return arg.split(RegExp(r'\s+')).first;
}

Duration? _cueTime(String mmssff) {
  final p = mmssff.split(':');
  if (p.length != 3) return null;
  final m = int.tryParse(p[0]);
  final s = int.tryParse(p[1]);
  final f = int.tryParse(p[2]);
  if (m == null || s == null || f == null || f >= 75 || s >= 60) return null;
  // 75 frames per second (Red Book).
  return Duration(milliseconds: (m * 60 + s) * 1000 + (f * 1000 ~/ 75));
}

/// Export (LIB-007): extended M3U8, UTF-8.
String writeM3u(List<PlaylistEntry> entries, {String? title}) {
  final b = StringBuffer('#EXTM3U\n');
  if (title != null) b.writeln('#PLAYLIST:${_oneLine(title)}');
  for (final e in entries) {
    final secs = e.duration == null ? -1 : e.duration!.inSeconds;
    final name = [?e.artist, ?e.title].map(_oneLine).join(' - ');
    b
      ..writeln('#EXTINF:$secs,$name')
      ..writeln(_oneLine(e.location));
  }
  return b.toString();
}

String writePls(List<PlaylistEntry> entries) {
  final b = StringBuffer('[playlist]\n');
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final n = i + 1;
    b.writeln('File$n=${_oneLine(e.location)}');
    if (e.title != null) b.writeln('Title$n=${_oneLine(e.title!)}');
    b.writeln('Length$n=${e.duration?.inSeconds ?? -1}');
  }
  b
    ..writeln('NumberOfEntries=${entries.length}')
    ..writeln('Version=2');
  return b.toString();
}

String writeXspf(List<PlaylistEntry> entries, {String? title}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<playlist version="1" xmlns="http://xspf.org/ns/0/">');
  if (title != null) b.writeln('  <title>${xmlEscape(title)}</title>');
  b.writeln('  <trackList>');
  for (final e in entries) {
    b
      ..writeln('    <track>')
      ..writeln('      <location>${xmlEscape(e.location)}</location>');
    if (e.title != null) {
      b.writeln('      <title>${xmlEscape(e.title!)}</title>');
    }
    if (e.artist != null) {
      b.writeln('      <creator>${xmlEscape(e.artist!)}</creator>');
    }
    if (e.album != null) {
      b.writeln('      <album>${xmlEscape(e.album!)}</album>');
    }
    if (e.duration != null) {
      b.writeln('      <duration>${e.duration!.inMilliseconds}</duration>');
    }
    b.writeln('    </track>');
  }
  b
    ..writeln('  </trackList>')
    ..writeln('</playlist>');
  return b.toString();
}

String _oneLine(String s) => s.replaceAll(RegExp(r'[\r\n]+'), ' ');
