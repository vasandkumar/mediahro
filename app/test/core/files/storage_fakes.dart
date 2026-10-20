import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// [FdIo] over dart:io files: "fds" are handles into an open-file table.
final class FakeFdIo implements FdIo {
  final Map<int, RandomAccessFile> open = {};
  var _next = 100;

  int register(File f, {bool write = false}) {
    open[++_next] = f.openSync(
      mode: write ? FileMode.writeOnly : FileMode.read,
    );
    return _next;
  }

  @override
  Uint8List pread(int fd, int offset, int length) {
    final f = open[fd]!..setPositionSync(offset);
    return f.readSync(length);
  }

  @override
  void pwrite(int fd, int offset, List<int> bytes) {
    open[fd]!
      ..setPositionSync(offset)
      ..writeFromSync(bytes);
  }

  @override
  int size(int fd) => open[fd]!.lengthSync();

  @override
  void close(int fd) => open.remove(fd)?.closeSync();
}

/// A SAF provider over a directory, as Android exposes one: opaque
/// `content://fake/doc/<id>` URIs, auto-renaming on name clashes
/// ("Name (1)"), fds through [io]. Also serves MediaStore entries and the
/// OS trash. Members a test does not need throw.
final class FakeSafStorage implements StorageFacade {
  FakeSafStorage(this.dir, this.io);

  final Directory dir;
  final FakeFdIo io;
  final List<MediaStoreEntry> media = [];
  final List<List<Uri>> trashed = [];
  final List<TrashResult> restored = [];
  int started = 0;
  int stopped = 0;

  static final Uri tree = Uri.parse('content://fake/tree/root');

  Uri _doc(String rel) =>
      Uri(scheme: 'content', host: 'fake', pathSegments: ['doc', rel]);

  String _rel(Uri uri) {
    if (uri == tree) return '';
    final segs = uri.pathSegments;
    if (uri.host != 'fake' || segs.length != 2 || segs.first != 'doc') {
      throw ArgumentError.value(uri, 'uri', 'not a document of this tree');
    }
    return segs[1];
  }

  String _path(String rel) =>
      rel.isEmpty ? dir.path : '${dir.path}${Platform.pathSeparator}$rel';

  DocumentEntry _entry(String rel) {
    final type = FileSystemEntity.typeSync(_path(rel));
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('no such document', rel);
    }
    final st = FileStat.statSync(_path(rel));
    final isDir = type == FileSystemEntityType.directory;
    return DocumentEntry(
      uri: _doc(rel),
      name: rel.split('/').last,
      isDirectory: isDir,
      size: isDir ? null : st.size,
      modified: st.modified,
    );
  }

  @override
  Future<ScopedAccess> startAccess(String grantId) async {
    started++;
    return _Scoped(tree, () async => stopped++);
  }

  @override
  Future<List<DocumentEntry>> listDocuments(Uri directory) async {
    final rel = _rel(directory);
    return [
      for (final e in Directory(_path(rel)).listSync())
        _entry(
          [
            if (rel.isNotEmpty) rel,
            e.uri.pathSegments.where((s) => s.isNotEmpty).last,
          ].join('/'),
        ),
    ];
  }

  @override
  Future<DocumentEntry> statDocument(Uri uri) async => _entry(_rel(uri));

  @override
  Future<int> openDocumentFd(
    Uri uri, {
    DocumentMode mode = DocumentMode.read,
  }) async {
    if (uri.host == 'media') {
      final e = media.firstWhere((m) => m.uri == uri);
      return io.register(File(_path('${e.relativePath}${e.name}')));
    }
    return io.register(
      File(_path(_rel(uri))),
      write: mode != DocumentMode.read,
    );
  }

  @override
  Future<Uri> createDocument(
    Uri parent,
    String name, {
    String? mimeType,
    bool directory = false,
  }) async {
    final p = _rel(parent);
    var n = name;
    for (
      var i = 1;
      FileSystemEntity.typeSync(_path([if (p.isNotEmpty) p, n].join('/'))) !=
          FileSystemEntityType.notFound;
      i++
    ) {
      n = '$name ($i)';
    }
    final rel = [if (p.isNotEmpty) p, n].join('/');
    if (directory) {
      Directory(_path(rel)).createSync();
    } else {
      File(_path(rel)).createSync();
    }
    return _doc(rel);
  }

  @override
  Future<Uri> renameDocument(Uri uri, String newName) async {
    final rel = _rel(uri);
    final parent = rel.contains('/')
        ? rel.substring(0, rel.lastIndexOf('/'))
        : '';
    final to = [if (parent.isNotEmpty) parent, newName].join('/');
    FileSystemEntity.isDirectorySync(_path(rel))
        ? Directory(_path(rel)).renameSync(_path(to))
        : File(_path(rel)).renameSync(_path(to));
    return _doc(to);
  }

  @override
  Future<Uri> moveDocument(
    Uri uri, {
    required Uri fromParent,
    required Uri toParent,
  }) async {
    final rel = _rel(uri);
    final to = [
      if (_rel(toParent).isNotEmpty) _rel(toParent),
      rel.split('/').last,
    ].join('/');
    FileSystemEntity.isDirectorySync(_path(rel))
        ? Directory(_path(rel)).renameSync(_path(to))
        : File(_path(rel)).renameSync(_path(to));
    return _doc(to);
  }

  @override
  Future<void> deleteDocument(Uri uri) async {
    final rel = _rel(uri);
    FileSystemEntity.isDirectorySync(_path(rel))
        ? Directory(_path(rel)).deleteSync(recursive: true)
        : File(_path(rel)).deleteSync();
  }

  @override
  Stream<MediaStoreEntry> mediaStoreEntries({
    required Set<PickKind> kinds,
    DateTime? modifiedSince,
  }) => Stream.fromIterable(media.where((m) => kinds.contains(m.kind)));

  @override
  Future<TrashResult> moveToTrash(List<Uri> uris) async {
    trashed.add(uris);
    return TrashResult(trashed: uris, undoToken: 't${trashed.length}');
  }

  @override
  Future<void> restoreFromTrash(TrashResult result) async =>
      restored.add(result);

  final List<(String, String, List<int>)> saved = [];
  final List<List<Uri>> shared = [];
  final List<Uri> opened = [];
  List<PickedFile> nextPick = const [];

  @override
  Future<Uri?> saveFile({
    required String suggestedName,
    required String mimeType,
    required Stream<List<int>> content,
  }) async {
    final bytes = [await for (final c in content) ...c];
    saved.add((suggestedName, mimeType, bytes));
    return Uri.parse('content://fake/saved/${saved.length}');
  }

  @override
  Future<void> share(List<Uri> uris, {String? subject}) async =>
      shared.add(uris);

  @override
  Future<bool> openWith(Uri uri) async {
    opened.add(uri);
    return true;
  }

  @override
  Future<List<PickedFile>> pickFiles({
    Set<PickKind> kinds = const {PickKind.any},
    bool multiple = false,
  }) async => nextPick;

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

final class _Scoped implements ScopedAccess {
  _Scoped(this.root, this._stop);

  @override
  final Uri root;
  final Future<void> Function() _stop;

  @override
  Future<void> stop() => _stop();
}
