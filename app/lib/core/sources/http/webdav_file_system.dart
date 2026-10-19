import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:mediahro/core/sources/http/http_file.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

const _propfindBody = '''
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop>
<d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:displayname/>
</d:prop></d:propfind>''';

/// WebDAV (NET-003): HTTPS, Basic/Digest, range reads; tested against
/// Nextcloud, ownCloud, Synology, Seafile and Apache mod_dav (docker env).
///
/// URIs use `dav://` / `davs://` (plain / TLS); they map to http(s) on the
/// wire. Plain `http(s)://` roots are accepted too.
final class WebDavFileSystem implements MutableFileSystem {
  WebDavFileSystem(this.session);

  final HttpSession session;

  @override
  Set<String> get schemes => const {'dav', 'davs', 'webdav', 'webdavs'};

  @override
  Set<VirtualFsCapability> get capabilities => const {
    VirtualFsCapability.list,
    VirtualFsCapability.write,
    VirtualFsCapability.rename,
    VirtualFsCapability.delete,
  };

  /// `davs://h/p` → `https://h/p`.
  static Uri wire(Uri uri) => switch (uri.scheme) {
    'dav' || 'webdav' => uri.replace(scheme: 'http'),
    'davs' || 'webdavs' => uri.replace(scheme: 'https'),
    _ => uri,
  };

  /// The scheme of [like] applied to a wire URI (keeps `davs://` in the UI).
  static Uri unwire(Uri wireUri, Uri like) => switch (like.scheme) {
    'dav' ||
    'webdav' ||
    'davs' ||
    'webdavs' => wireUri.replace(scheme: like.scheme),
    _ => wireUri,
  };

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final dir = directory.path.endsWith('/')
        ? directory
        : directory.replace(path: '${directory.path}/');
    final entries = await _propfind(dir, depth: '1');
    for (final e in entries) {
      if (_samePath(e.uri.path, dir.path)) continue;
      yield e;
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final e = await _propfind(uri, depth: '0');
    if (e.isEmpty) throw VirtualFileException(VirtualFileError.notFound, uri);
    return e.first;
  }

  @override
  Future<VirtualFile> open(Uri uri) async {
    final f = await HttpVirtualFile.open(wire(uri), session);
    return _Renamed(f, uri);
  }

  @override
  Future<Uri> createDirectory(Uri parent, String name) async {
    final uri = _child(parent, name, directory: true);
    final (status, _, _) = await session.fetch('MKCOL', wire(uri));
    if (status == 405) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    HttpSession.check(status, uri);
    return uri;
  }

  @override
  Future<Uri> rename(Uri uri, String newName) {
    final parentPath = _parentPath(uri.path);
    final isDir = uri.path.endsWith('/');
    final target = uri.replace(
      path: '$parentPath${Uri.encodeComponent(newName)}${isDir ? '/' : ''}',
    );
    return _move(uri, target);
  }

  @override
  Future<Uri> move(Uri uri, Uri directory) {
    final name = uri.pathSegments.where((s) => s.isNotEmpty).last;
    return _move(
      uri,
      _child(directory, name, directory: uri.path.endsWith('/')),
    );
  }

  @override
  Future<void> delete(Uri uri, {bool recursive = false}) async {
    if (!recursive && uri.path.endsWith('/')) {
      final children = await list(uri).take(1).toList();
      if (children.isNotEmpty) {
        throw VirtualFileException(
          VirtualFileError.io,
          uri,
          'folder is not empty',
        );
      }
    }
    final (status, _, _) = await session.fetch('DELETE', wire(uri));
    HttpSession.check(status, uri);
  }

  @override
  Future<VirtualFileWriter> create(Uri uri) async {
    final tmp = await Directory.systemTemp.createTemp('mediahro_put');
    return _DavWriter(
      this,
      uri,
      File('${tmp.path}${Platform.pathSeparator}body'),
      tmp,
    );
  }

  Future<Uri> _move(Uri from, Uri to) async {
    final (status, _, _) = await session.fetch(
      'MOVE',
      wire(from),
      extra: {'Destination': wire(to).toString(), 'Overwrite': 'F'},
    );
    HttpSession.check(status, from);
    return to;
  }

  Future<List<VirtualEntry>> _propfind(Uri uri, {required String depth}) async {
    final (status, _, body) = await session.fetch(
      'PROPFIND',
      wire(uri),
      extra: {'Depth': depth, 'Content-Type': 'application/xml; charset=utf-8'},
      body: utf8.encode(_propfindBody),
    );
    if (status != 207) HttpSession.check(status == 200 ? 502 : status, uri);
    return parseMultistatus(utf8.decode(body, allowMalformed: true), uri);
  }

  static Uri _child(Uri dir, String name, {required bool directory}) {
    final base = dir.path.endsWith('/') ? dir.path : '${dir.path}/';
    return dir.replace(
      path: '$base${Uri.encodeComponent(name)}${directory ? '/' : ''}',
    );
  }

  static String _parentPath(String path) {
    final p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    return p.substring(0, p.lastIndexOf('/') + 1);
  }

  static bool _samePath(String a, String b) {
    String n(String s) =>
        Uri.decodeFull(s.endsWith('/') ? s.substring(0, s.length - 1) : s);
    return n(a) == n(b);
  }
}

/// Parses a `207 Multi-Status` PROPFIND response. Hrefs are resolved
/// against [request] and keep its scheme.
List<VirtualEntry> parseMultistatus(String xml, Uri request) {
  final root = parseXml(
    xml,
    limits: const XmlLimits(maxLength: 32 << 20, maxNodes: 2000000),
  );
  final out = <VirtualEntry>[];
  for (final r in root.all('response')) {
    final href = r.childText('href');
    if (href == null) continue;
    XmlElement? prop;
    for (final ps in r.all('propstat')) {
      final status = ps.childText('status') ?? '';
      if (status.contains(' 200 ')) prop = ps.child('prop');
    }
    if (prop == null) continue;
    final isDir = prop.child('resourcetype')?.child('collection') != null;
    final resolved = request.resolve(href.trim());
    final uri = request.replace(path: resolved.path);
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final name = prop.childText('displayname');
    final modified = prop.childText('getlastmodified');
    out.add(
      VirtualEntry(
        uri: isDir && !uri.path.endsWith('/')
            ? uri.replace(path: '${uri.path}/')
            : uri,
        name: segs.isEmpty ? (name ?? '') : segs.last,
        isDirectory: isDir,
        size: isDir
            ? null
            : int.tryParse(prop.childText('getcontentlength') ?? ''),
        modified: modified == null ? null : _httpDate(modified),
      ),
    );
  }
  return out;
}

DateTime? _httpDate(String s) {
  try {
    return HttpDate.parse(s);
  } on FormatException {
    return DateTime.tryParse(s);
  }
}

final class _Renamed implements VirtualFile {
  _Renamed(this._inner, this.uri);

  final VirtualFile _inner;
  @override
  final Uri uri;

  @override
  bool get isSeekable => _inner.isSeekable;
  @override
  Future<int?> length() => _inner.length();
  @override
  Future<Uint8List> read(int offset, int length) => _inner.read(offset, length);
  @override
  Future<void> close() => _inner.close();
}

/// Buffers to a temp file, then one streamed PUT on close.
final class _DavWriter implements VirtualFileWriter {
  _DavWriter(this._fs, this.uri, this._file, this._dir);

  final WebDavFileSystem _fs;
  @override
  final Uri uri;
  final File _file;
  final Directory _dir;
  IOSink? _sink;

  @override
  Future<void> write(List<int> bytes) async {
    (_sink ??= _file.openWrite()).add(bytes);
  }

  @override
  Future<void> close() async {
    try {
      await _sink?.close();
      if (!_file.existsSync()) await _file.create();
      final len = await _file.length();
      final res = await _fs.session.send(
        'PUT',
        WebDavFileSystem.wire(uri),
        bodyStream: _file.openRead,
        contentLength: len,
      );
      await res.body.drain<void>();
      HttpSession.check(res.statusCode, uri);
    } finally {
      await _dir.delete(recursive: true);
    }
  }

  @override
  Future<void> abort() async {
    await _sink?.close();
    await _dir.delete(recursive: true);
  }
}
