import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Android's MediaStore video, audio and pictures (LIB-002 "MediaStore + SAF trees")
/// as a read-only, path-shaped file system: `mediastore:///Movies/Holiday/
/// a.mkv` from each entry's `RELATIVE_PATH`, so the scanner, the index and
/// the browser treat it like any folder tree. One MediaStore query per
/// instance (one per scan); bytes come through a detached fd and [FdIo].
/// Deletion goes through [StorageFacade.moveToTrash] with [contentUri]
/// (MediaStore trash), not through this file system.
final class MediaStoreFileSystem implements ClosableFileSystem {
  MediaStoreFileSystem(
    this.storage, {
    FdIo? io,
    this.kinds = const {PickKind.video, PickKind.audio, PickKind.image},
  }) : io = io ?? PosixFdIo();

  static final Uri root = Uri.parse('mediastore:///');

  final StorageFacade storage;
  final FdIo io;
  final Set<PickKind> kinds;

  Future<_Tree>? _tree;

  @override
  Set<String> get schemes => const {'mediastore'};

  @override
  Set<VirtualFsCapability> get capabilities => const {VirtualFsCapability.list};

  Future<_Tree> _load(Uri uri) => _tree ??= () async {
    final t = _Tree();
    try {
      await for (final e in storage.mediaStoreEntries(kinds: kinds)) {
        final dir = e.relativePath
            .split('/')
            .where((s) => s.isNotEmpty && s != '.' && s != '..')
            .toList();
        t.files[[...dir, e.name].join('/')] = e;
        for (var i = 0; i <= dir.length; i++) {
          final parent = dir.sublist(0, i).join('/');
          if (i < dir.length) {
            (t.dirs[parent] ??= <String>{}).add(dir[i]);
          } else {
            (t.fileNames[parent] ??= <String>{}).add(e.name);
          }
        }
      }
    } on Exception catch (e) {
      _tree = null;
      throw VirtualFileException(VirtualFileError.io, uri, '$e');
    }
    return t;
  }();

  List<String> _segments(Uri uri) {
    if (uri.scheme != 'mediastore') {
      throw VirtualFileException(VirtualFileError.notFound, uri);
    }
    return uri.pathSegments.where((s) => s.isNotEmpty).toList();
  }

  Uri _uriOf(List<String> rel) => root.replace(pathSegments: rel);

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final t = await _load(directory);
    final key = _segments(directory).join('/');
    if (key.isNotEmpty &&
        !t.dirs.containsKey(key) &&
        !t.fileNames.containsKey(key)) {
      throw VirtualFileException(VirtualFileError.notFound, directory);
    }
    final rel = _segments(directory);
    for (final d in t.dirs[key] ?? const <String>{}) {
      yield VirtualEntry(uri: _uriOf([...rel, d]), name: d, isDirectory: true);
    }
    for (final f in t.fileNames[key] ?? const <String>{}) {
      final e = t.files[[...rel, f].join('/')]!;
      yield VirtualEntry(
        uri: _uriOf([...rel, f]),
        name: f,
        isDirectory: false,
        size: e.size,
        modified: e.modified,
      );
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final t = await _load(uri);
    final rel = _segments(uri);
    final key = rel.join('/');
    if (t.files[key] case final e?) {
      return VirtualEntry(
        uri: uri,
        name: e.name,
        isDirectory: false,
        size: e.size,
        modified: e.modified,
      );
    }
    if (key.isEmpty ||
        t.dirs.containsKey(key) ||
        t.fileNames.containsKey(key)) {
      return VirtualEntry(
        uri: uri,
        name: rel.isEmpty ? '/' : rel.last,
        isDirectory: true,
      );
    }
    throw VirtualFileException(VirtualFileError.notFound, uri);
  }

  /// The `content://media/…` URI behind [uri] (share, open-in, trash).
  Future<Uri> contentUri(Uri uri) async {
    final e = (await _load(uri)).files[_segments(uri).join('/')];
    if (e == null) throw VirtualFileException(VirtualFileError.notFound, uri);
    return e.uri;
  }

  @override
  Future<VirtualFile> open(Uri uri) async {
    final e = (await _load(uri)).files[_segments(uri).join('/')];
    if (e == null) throw VirtualFileException(VirtualFileError.notFound, uri);
    final int fd;
    try {
      fd = await storage.openDocumentFd(e.uri);
    } on Exception catch (x) {
      throw VirtualFileException(VirtualFileError.io, uri, '$x');
    }
    return _MediaFile(io, fd, uri, e.size);
  }

  @override
  Future<void> close() async => _tree = null;
}

final class _Tree {
  final Map<String, MediaStoreEntry> files = {};

  /// Directory path → child directory names.
  final Map<String, Set<String>> dirs = {};

  /// Directory path → file names.
  final Map<String, Set<String>> fileNames = {};
}

final class _MediaFile implements VirtualFile {
  _MediaFile(this._io, this._fd, this.uri, this._length);

  final FdIo _io;
  final int _fd;
  @override
  final Uri uri;
  final int _length;
  bool _closed = false;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => _length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    if (length <= 0 || offset >= _length) return Uint8List(0);
    try {
      return _io.pread(_fd, offset, length);
    } on Exception catch (e) {
      throw VirtualFileException(VirtualFileError.io, uri, '$e');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _io.close(_fd);
  }
}
