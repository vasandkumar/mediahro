import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// A granted Android SAF tree (LIB-002, FILE-001/002) as a path-shaped file
/// system: `saf://tree/<grantId>/Films/Movie.mkv`.
///
/// SAF document URIs are opaque and cannot be composed from a parent and a
/// name, but the scanner, the index (relative paths), file operations and
/// sidecar handling all work on paths. So this file system speaks paths and
/// maps each one to its document URI by walking the tree through
/// [StorageFacade.listDocuments] (cached per directory). Bytes move through
/// a detached fd ([StorageFacade.openDocumentFd]) with pread/pwrite
/// ([FdIo]), which also gives the player random access.
///
/// Runs on the main isolate (the facade is a platform channel); reads are
/// positional syscalls on local storage.
final class SafFileSystem implements MutableFileSystem, ClosableFileSystem {
  SafFileSystem(
    this.storage, {
    required this.tree,
    required this.root,
    FdIo? io,
  }) : io = io ?? PosixFdIo();

  /// `saf://tree/<grantId>/` for a grant.
  static Uri rootFor(String grantId) =>
      Uri(scheme: 'saf', host: 'tree', pathSegments: [grantId, '']);

  final StorageFacade storage;

  /// The SAF tree URI of the grant (`content://…/tree/…`).
  final Uri tree;

  /// [rootFor] of the grant; every URI this file system serves is below it.
  final Uri root;
  final FdIo io;

  /// Path below [root] (no leading/trailing slash) → document entry.
  final Map<String, DocumentEntry> _known = {};

  /// Directory path → its children by name, filled by listings.
  final Map<String, Map<String, DocumentEntry>> _children = {};

  @override
  Set<String> get schemes => const {'saf'};

  @override
  Set<VirtualFsCapability> get capabilities => const {
    VirtualFsCapability.list,
    VirtualFsCapability.write,
    VirtualFsCapability.rename,
    VirtualFsCapability.delete,
  };

  List<String> _segments(Uri uri) {
    final rootSegs = root.pathSegments.where((s) => s.isNotEmpty).toList();
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.scheme != 'saf' ||
        uri.host != root.host ||
        segs.length < rootSegs.length ||
        !_startsWith(segs, rootSegs)) {
      throw VirtualFileException(
        VirtualFileError.notFound,
        uri,
        'not in this tree',
      );
    }
    return segs.sublist(rootSegs.length);
  }

  static bool _startsWith(List<String> a, List<String> b) {
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Uri _uriOf(List<String> rel, {bool directory = false}) => root.replace(
    pathSegments: [
      ...root.pathSegments.where((s) => s.isNotEmpty),
      ...rel,
      if (directory) '',
    ],
  );

  Future<Map<String, DocumentEntry>> _list(List<String> rel, Uri uri) async {
    final key = rel.join('/');
    final doc = rel.isEmpty ? tree : (await _entry(rel, uri)).uri;
    final entries = await _guard(uri, () => storage.listDocuments(doc));
    final byName = {for (final e in entries) e.name: e};
    _children[key] = byName;
    for (final e in entries) {
      _known[[...rel, e.name].join('/')] = e;
    }
    return byName;
  }

  /// The document for [rel], walking down from the tree root on a miss.
  Future<DocumentEntry> _entry(List<String> rel, Uri uri) async {
    final key = rel.join('/');
    if (_known[key] case final e?) return e;
    if (rel.isEmpty) {
      throw VirtualFileException(VirtualFileError.notFound, uri, 'tree root');
    }
    final parent = rel.sublist(0, rel.length - 1);
    final siblings = _children[parent.join('/')] ?? await _list(parent, uri);
    final e = siblings[rel.last];
    if (e == null) throw VirtualFileException(VirtualFileError.notFound, uri);
    return e;
  }

  void _forget(List<String> rel) {
    final key = rel.join('/');
    _known.removeWhere((k, _) => k == key || k.startsWith('$key/'));
    _children.removeWhere((k, _) => k == key || k.startsWith('$key/'));
    // The parent's listing is stale now: drop it so the next lookup re-lists.
    if (rel.isNotEmpty) {
      _children.remove(rel.sublist(0, rel.length - 1).join('/'));
    }
  }

  VirtualEntry _virtual(List<String> rel, DocumentEntry e) => VirtualEntry(
    uri: _uriOf(rel),
    name: e.name,
    isDirectory: e.isDirectory,
    size: e.isDirectory ? null : e.size,
    modified: e.modified,
  );

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final rel = _segments(directory);
    final children = await _list(rel, directory);
    for (final e in children.values) {
      yield _virtual([...rel, e.name], e);
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final rel = _segments(uri);
    if (rel.isEmpty) {
      return VirtualEntry(uri: root, name: '/', isDirectory: true);
    }
    return _virtual(rel, await _entry(rel, uri));
  }

  @override
  Future<VirtualFile> open(Uri uri) async {
    final rel = _segments(uri);
    final e = await _entry(rel, uri);
    if (e.isDirectory) {
      throw VirtualFileException(
        VirtualFileError.notFound,
        uri,
        'is a directory',
      );
    }
    final fd = await _guard(uri, () => storage.openDocumentFd(e.uri));
    return _FdFile(io, fd, uri, e.size ?? io.size(fd));
  }

  /// The SAF document URI behind [uri] (share, open-in, the player).
  Future<Uri> documentUri(Uri uri) async {
    final rel = _segments(uri);
    return rel.isEmpty ? tree : (await _entry(rel, uri)).uri;
  }

  Future<DocumentEntry> _parentDoc(List<String> rel, Uri uri) async =>
      rel.length <= 1
      ? DocumentEntry(uri: tree, name: '', isDirectory: true)
      : await _entry(rel.sublist(0, rel.length - 1), uri);

  Future<bool> _exists(List<String> rel, Uri uri) async {
    try {
      await _entry(rel, uri);
      return true;
    } on VirtualFileException {
      return false;
    }
  }

  static String _checkName(String name, Uri uri) {
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
      throw VirtualFileException(VirtualFileError.notFound, uri, 'bad name');
    }
    return name;
  }

  @override
  Future<Uri> createDirectory(Uri parent, String name) async {
    final rel = [..._segments(parent), _checkName(name, parent)];
    final target = _uriOf(rel, directory: true);
    // SAF renames on conflict ("Name (1)"); refuse instead, like the others.
    if (await _exists(rel, target)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, target);
    }
    final p = await _parentDoc(rel, target);
    final made = await _guard(
      target,
      () => storage.createDocument(p.uri, name, directory: true),
    );
    _forget(rel.sublist(0, rel.length - 1));
    _known[rel.join('/')] = DocumentEntry(
      uri: made,
      name: name,
      isDirectory: true,
    );
    return target;
  }

  @override
  Future<Uri> rename(Uri uri, String newName) async {
    final rel = _segments(uri);
    final target = [
      ...rel.sublist(0, rel.length - 1),
      _checkName(newName, uri),
    ];
    final targetUri = _uriOf(target);
    if (await _exists(target, targetUri)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, targetUri);
    }
    final e = await _entry(rel, uri);
    await _guard(uri, () => storage.renameDocument(e.uri, newName));
    _forget(rel);
    _forget(target);
    return targetUri;
  }

  @override
  Future<Uri> move(Uri uri, Uri directory) async {
    final rel = _segments(uri);
    final dirRel = _segments(directory);
    final target = [...dirRel, rel.last];
    final targetUri = _uriOf(target);
    if (await _exists(target, targetUri)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, targetUri);
    }
    final e = await _entry(rel, uri);
    final from = await _parentDoc(rel, uri);
    final to = dirRel.isEmpty
        ? DocumentEntry(uri: tree, name: '', isDirectory: true)
        : await _entry(dirRel, directory);
    await _guard(
      uri,
      () => storage.moveDocument(e.uri, fromParent: from.uri, toParent: to.uri),
    );
    _forget(rel);
    _forget(target);
    return targetUri;
  }

  @override
  Future<void> delete(Uri uri, {bool recursive = false}) async {
    final rel = _segments(uri);
    final e = await _entry(rel, uri);
    if (e.isDirectory && !recursive && (await _list(rel, uri)).isNotEmpty) {
      throw VirtualFileException(VirtualFileError.io, uri, 'folder not empty');
    }
    await _guard(uri, () => storage.deleteDocument(e.uri));
    _forget(rel);
  }

  @override
  Future<VirtualFileWriter> create(Uri uri) async {
    final rel = _segments(uri);
    if (rel.isEmpty) throw VirtualFileException(VirtualFileError.notFound, uri);
    if (await _exists(rel, uri)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    final p = await _parentDoc(rel, uri);
    final made = await _guard(
      uri,
      () => storage.createDocument(p.uri, rel.last),
    );
    _forget(rel.sublist(0, rel.length - 1));
    final fd = await _guard(
      uri,
      () => storage.openDocumentFd(made, mode: DocumentMode.write),
    );
    return _FdWriter(this, io, fd, uri, made);
  }

  @override
  Future<void> close() async {
    _known.clear();
    _children.clear();
  }

  Future<T> _guard<T>(Uri uri, Future<T> Function() op) async {
    try {
      return await op();
    } on VirtualFileException {
      rethrow;
      // The facade's documented answer off Android (StorageFacade).
      // ignore: avoid_catching_errors
    } on UnsupportedError catch (e) {
      throw VirtualFileException(VirtualFileError.unsupported, uri, '$e');
    } on Exception catch (e) {
      throw VirtualFileException(VirtualFileError.io, uri, '$e');
    }
  }
}

final class _FdFile implements VirtualFile {
  _FdFile(this._io, this._fd, this.uri, this._length);

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

final class _FdWriter implements VirtualFileWriter {
  _FdWriter(this._fs, this._io, this._fd, this.uri, this._document);

  final SafFileSystem _fs;
  final FdIo _io;
  final int _fd;
  @override
  final Uri uri;
  final Uri _document;
  var _offset = 0;
  var _ended = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (_ended) throw VirtualFileException(VirtualFileError.closed, uri);
    try {
      _io.pwrite(_fd, _offset, bytes);
    } on Exception catch (e) {
      throw VirtualFileException(VirtualFileError.io, uri, '$e');
    }
    _offset += bytes.length;
  }

  @override
  Future<void> close() async {
    if (_ended) return;
    _ended = true;
    _io.close(_fd);
  }

  @override
  Future<void> abort() async {
    if (_ended) return;
    _ended = true;
    _io.close(_fd);
    try {
      await _fs.storage.deleteDocument(_document);
    } on Object catch (_) {
      // the partial document stays if the provider refuses
    }
  }
}
