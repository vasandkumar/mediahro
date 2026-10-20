import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

/// A subtitle file ready for `PlaybackEngine.addExternalTrack`.
@immutable
final class ExternalSubtitle {
  const ExternalSubtitle({
    required this.file,
    required this.title,
    this.source,
    this.language,
    this.forced = false,
    this.hearingImpaired = false,
  });

  /// A local `file:` copy the engine can read.
  final Uri file;

  /// Where the file really lives (for saving edits next to it, SUB-030).
  final Uri? source;
  final String title;
  final String? language;
  final bool forced;
  final bool hearingImpaired;
}

/// Finds subtitle files that belong to a video wherever it lives (SUB-012)
/// and copies them to a local cache for the engine.
///
/// mpv finds sidecars of local files itself (`sub-auto`, `Subs/`); videos
/// on network shares, WebDAV, SAF and servers reach it as streams, so their
/// folders are listed here through the [VirtualFileSystem]. The user's
/// subtitle folder is searched for every video.
final class SidecarLoader {
  SidecarLoader({
    required this.fileSystemFor,
    required this.cacheDir,
    this.maxBytes = 20 * 1024 * 1024,
  });

  /// The file system serving a URI (mounted sources, local files).
  final VirtualFileSystem Function(Uri uri) fileSystemFor;
  final Directory cacheDir;

  /// Larger files are skipped (PRIV-005, as `ParseLimits.maxBytes`).
  final int maxBytes;

  /// Sidecars of [video]. Its own folder (and `Subs/`) is searched unless
  /// [ownFolder] is false; [userFolder] is searched by name.
  Future<List<ExternalSubtitle>> find(
    Uri video, {
    bool ownFolder = true,
    Uri? userFolder,
  }) async {
    final name = video.pathSegments.isEmpty
        ? ''
        : Uri.decodeComponent(video.pathSegments.last);
    if (name.isEmpty) return const [];
    final found = <ExternalSubtitle>[];
    final target = Directory(
      '${cacheDir.path}/${sha1.convert(utf8.encode(video.toString()))}',
    );
    if (ownFolder) {
      final folder = video.resolve('.');
      final files = <(String, String)>[];
      final byPath = <String, Uri>{};
      Future<void> scan(Uri dir, String rel) async {
        for (final e in await _list(dir)) {
          final key = rel.isEmpty ? e.name : '$rel/${e.name}';
          if (e.isDirectory) {
            if (rel.isEmpty && e.name.toLowerCase() == 'subs') {
              await scan(e.uri, e.name);
            } else if (rel.toLowerCase() == 'subs' &&
                e.name.toLowerCase() == _stem(name).toLowerCase()) {
              await scan(e.uri, key);
            }
          } else if (isSubtitleName(e.name)) {
            files.add((rel, e.name));
            byPath[key] = e.uri;
          }
        }
      }

      await scan(folder, '');
      found.addAll(await _copy(matchSidecars(name, files), byPath, target));
    }
    if (userFolder != null) {
      final byPath = <String, Uri>{};
      final files = <(String, String)>[];
      for (final e in await _list(userFolder)) {
        if (!e.isDirectory && isSubtitleName(e.name)) {
          files.add(('', e.name));
          byPath[e.name] = e.uri;
        }
      }
      found.addAll(await _copy(matchSidecars(name, files), byPath, target));
    }
    return found;
  }

  static String _stem(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? name : name.substring(0, i);
  }

  Future<List<VirtualEntry>> _list(Uri dir) async {
    try {
      return await fileSystemFor(dir).list(dir).toList();
    } on VirtualFileException {
      return const [];
    }
  }

  Future<List<ExternalSubtitle>> _copy(
    List<SidecarMatch> matches,
    Map<String, Uri> byPath,
    Directory target,
  ) async {
    final out = <ExternalSubtitle>[];
    for (final m in matches) {
      final source = byPath[m.path];
      if (source == null) continue;
      final dir = Directory(
        m.folder.isEmpty ? target.path : '${target.path}/${m.folder}',
      );
      final local = await _fetch(source, File('${dir.path}/${m.name}'));
      if (local == null) continue;
      for (final c in m.companions) {
        final cs = byPath[m.folder.isEmpty ? c : '${m.folder}/$c'];
        if (cs != null) await _fetch(cs, File('${dir.path}/$c'));
      }
      out.add(
        ExternalSubtitle(
          file: local.uri,
          source: source,
          title: m.name,
          language: m.language,
          forced: m.forced,
          hearingImpaired: m.hearingImpaired,
        ),
      );
    }
    return out;
  }

  Future<File?> _fetch(Uri source, File to) async {
    VirtualFile? f;
    try {
      f = await fileSystemFor(source).open(source);
      final len = await f.length();
      if (len == null || len > maxBytes) return null;
      final bytes = await f.read(0, len);
      await to.parent.create(recursive: true);
      await to.writeAsBytes(bytes, flush: true);
      return to;
    } on VirtualFileException {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      await f?.close();
    }
  }

  /// Copies a picked or dropped subtitle into the cache (SUB-012).
  Future<File?> store(String name, List<int> bytes) async {
    if (bytes.length > maxBytes) return null;
    final to = File('${cacheDir.path}/picked/$name');
    await to.parent.create(recursive: true);
    await to.writeAsBytes(bytes, flush: true);
    return to;
  }
}
