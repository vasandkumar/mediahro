import 'dart:async';

import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/http/http_file.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// One DIDL-Lite object (container or item).
@immutable
final class DidlObject {
  const DidlObject({
    required this.id,
    required this.title,
    required this.isContainer,
    this.upnpClass = '',
    this.resource,
    this.mime,
    this.size,
    this.duration,
    this.artist,
    this.album,
    this.albumArtUri,
    this.resolution,
  });

  final String id;
  final String title;
  final bool isContainer;
  final String upnpClass;
  final Uri? resource;
  final String? mime;
  final int? size;
  final Duration? duration;
  final String? artist;
  final String? album;
  final Uri? albumArtUri;
  final String? resolution;

  /// File-like name: title plus an extension from the resource.
  String get fileName {
    if (isContainer) return title;
    final ext = _extension();
    final t = title.replaceAll('/', '∕');
    return ext == null || t.toLowerCase().endsWith('.$ext') ? t : '$t.$ext';
  }

  String? _extension() {
    final path = resource?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot > path.lastIndexOf('/') && path.length - dot <= 6) {
      return path.substring(dot + 1).toLowerCase();
    }
    return switch (mime) {
      'video/x-matroska' => 'mkv',
      'video/mp4' => 'mp4',
      'video/mpeg' => 'mpg',
      'video/x-msvideo' => 'avi',
      'audio/mpeg' => 'mp3',
      'audio/flac' || 'audio/x-flac' => 'flac',
      'audio/mp4' => 'm4a',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      _ => null,
    };
  }
}

/// Parses a DIDL-Lite `Result` document (ContentDirectory:1 Browse).
List<DidlObject> parseDidl(String xml) {
  final root = parseXml(
    xml,
    limits: const XmlLimits(maxLength: 16 << 20, maxNodes: 500000),
  );
  final out = <DidlObject>[];
  for (final e in root.children) {
    final container = e.localName == 'container';
    if (!container && e.localName != 'item') continue;
    final id = e.attr('id');
    if (id == null) continue;
    XmlElement? res;
    for (final r in e.all('res')) {
      // Prefer the original (non-transcoded) resource.
      final pi = r.attr('protocolInfo') ?? '';
      if (res == null || pi.contains('DLNA.ORG_CI=0')) res = r;
    }
    final protocolInfo = res?.attr('protocolInfo')?.split(':');
    out.add(
      DidlObject(
        id: id,
        title: e.childText('title') ?? id,
        isContainer: container,
        upnpClass: e.childText('class') ?? '',
        resource: res == null ? null : Uri.tryParse(res.text),
        mime: protocolInfo != null && protocolInfo.length >= 3
            ? protocolInfo[2]
            : null,
        size: int.tryParse(res?.attr('size') ?? ''),
        duration: _duration(res?.attr('duration')),
        resolution: res?.attr('resolution'),
        artist: e.childText('artist') ?? e.childText('creator'),
        album: e.childText('album'),
        albumArtUri: Uri.tryParse(e.childText('albumArtURI') ?? ''),
      ),
    );
  }
  return out;
}

Duration? _duration(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?').firstMatch(s);
  if (m == null) return null;
  final frac = m.group(4);
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: frac == null
        ? 0
        : int.parse(frac.padRight(3, '0').substring(0, 3)),
  );
}

/// The root of the DLNA source for a device's UDN (`uuid:…`): the UDN
/// without its `uuid:` prefix is the host, so the URI parses back.
Uri dlnaRootUri(String udn) =>
    Uri(scheme: 'dlna', host: udn.replaceFirst('uuid:', ''), path: '/');

/// DLNA/UPnP media server browsing (NET-005) as a path-addressed file
/// system: `dlna://<udn>/<container titles>/<item name>`. Paths map to
/// object ids by browsing; results are cached per container. Duplicate
/// titles in one container get a ` [n]` suffix so every path is unique.
final class DlnaFileSystem implements VirtualFileSystem {
  DlnaFileSystem(this.session, this.contentDirectory, {this.pageSize = 200});

  final HttpSession session;
  final UpnpService contentDirectory;
  final int pageSize;
  final _children = <String, List<(String, DidlObject)>>{};

  @override
  Set<String> get schemes => const {'dlna'};

  @override
  Set<VirtualFsCapability> get capabilities => const {VirtualFsCapability.list};

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final id = await _resolve(directory, wantContainer: true);
    for (final (name, o) in await _browse(id)) {
      yield VirtualEntry(
        uri: _uri(directory, name, container: o.isContainer),
        name: name,
        isDirectory: o.isContainer,
        size: o.size,
      );
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final o = await _object(uri);
    final segs = _segments(uri);
    return VirtualEntry(
      uri: uri,
      name: segs.isEmpty ? '' : segs.last,
      isDirectory: o?.isContainer ?? true,
      size: o?.size,
    );
  }

  @override
  Future<VirtualFile> open(Uri uri) async {
    final o = await _object(uri);
    final res = o?.resource;
    if (o == null || o.isContainer || res == null) {
      throw VirtualFileException(VirtualFileError.notFound, uri);
    }
    return await HttpVirtualFile.open(res, session, knownLength: o.size);
  }

  /// The DIDL object at [uri] (null for the root).
  Future<DidlObject?> describe(Uri uri) => _object(uri);

  void invalidate() => _children.clear();

  Future<DidlObject?> _object(Uri uri) async {
    final segs = _segments(uri);
    if (segs.isEmpty) return null;
    final parent = await _resolveSegments(
      segs.sublist(0, segs.length - 1),
      uri,
    );
    for (final (name, o) in await _browse(parent)) {
      if (name == segs.last) return o;
    }
    throw VirtualFileException(VirtualFileError.notFound, uri);
  }

  Future<String> _resolve(Uri uri, {required bool wantContainer}) =>
      _resolveSegments(_segments(uri), uri);

  Future<String> _resolveSegments(List<String> segs, Uri uri) async {
    var id = '0';
    for (final s in segs) {
      final match = (await _browse(id))
          .where((c) => c.$1 == s && c.$2.isContainer)
          .firstOrNull;
      if (match == null) {
        throw VirtualFileException(VirtualFileError.notFound, uri);
      }
      id = match.$2.id;
    }
    return id;
  }

  Future<List<(String, DidlObject)>> _browse(String objectId) async {
    final cached = _children[objectId];
    if (cached != null) return cached;
    final all = <DidlObject>[];
    var start = 0;
    while (true) {
      final Map<String, String> r;
      try {
        r = await soapCall(session, contentDirectory, 'Browse', {
          'ObjectID': objectId,
          'BrowseFlag': 'BrowseDirectChildren',
          'Filter': '*',
          'StartingIndex': '$start',
          'RequestedCount': '$pageSize',
          'SortCriteria': '',
        });
      } on UpnpError catch (e) {
        throw VirtualFileException(
          e.code == 701 ? VirtualFileError.notFound : VirtualFileError.io,
          Uri(scheme: 'dlna', path: objectId),
          '$e',
        );
      }
      final page = parseDidl(r['Result'] ?? '<DIDL-Lite/>');
      all.addAll(page);
      final returned = int.tryParse(r['NumberReturned'] ?? '') ?? page.length;
      final total = int.tryParse(r['TotalMatches'] ?? '') ?? 0;
      start += returned;
      if (returned == 0 ||
          (total > 0 && start >= total) ||
          (total == 0 && page.length < pageSize)) {
        break;
      }
      if (all.length > 100000) break;
    }
    final used = <String, int>{};
    final named = <(String, DidlObject)>[];
    for (final o in all) {
      final base = o.fileName.isEmpty ? o.id : o.fileName;
      final n = used[base] = (used[base] ?? 0) + 1;
      named.add((n == 1 ? base : '$base [$n]', o));
    }
    return _children[objectId] = named;
  }

  static List<String> _segments(Uri uri) =>
      uri.pathSegments.where((s) => s.isNotEmpty).toList();

  static Uri _uri(Uri dir, String name, {required bool container}) =>
      dir.replace(pathSegments: [..._segments(dir), name, if (container) '']);
}
