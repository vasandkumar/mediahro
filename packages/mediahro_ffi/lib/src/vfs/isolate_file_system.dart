import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro_ffi/src/vfs/virtual_file.dart';

/// A blocking protocol client (libsmb2, libnfs, libcurl, libarchive) that
/// runs on its own worker isolate: one isolate per mounted source
/// (docs/05 §7, "a network isolate per source"). Paths are `/`-separated
/// and relative to the source root (`''` is the root).
abstract interface class SyncFileSystem {
  List<VirtualEntry> list(String path);
  VirtualEntry stat(String path);

  /// Opens a file and returns a handle.
  int open(String path, {bool write = false, bool create = false});
  int? length(int handle);
  Uint8List read(int handle, int offset, int length);
  void write(int handle, int offset, List<int> bytes);
  void close(int handle);
  void mkdir(String path);
  void rename(String from, String to);
  void unlink(String path);
  void rmdir(String path);

  /// Releases the connection (called on the worker before it exits).
  void dispose();
}

/// Builds the [SyncFileSystem] inside the worker. Must capture only
/// sendable values (host, share, resolved credentials).
typedef SyncFileSystemFactory = SyncFileSystem Function();

/// Async [MutableFileSystem] over a [SyncFileSystem] hosted on a worker
/// isolate. URIs below [root] map to paths by their decoded segments.
final class IsolateFileSystem implements MutableFileSystem {
  IsolateFileSystem({
    required this.root,
    required this._factory,
    required this.schemes,
    this.capabilities = const {
      VirtualFsCapability.list,
      VirtualFsCapability.write,
      VirtualFsCapability.rename,
      VirtualFsCapability.delete,
    },
    this.debugName = 'mediahro-vfs',
  });

  final Uri root;
  final SyncFileSystemFactory _factory;
  final String debugName;

  @override
  final Set<String> schemes;

  @override
  final Set<VirtualFsCapability> capabilities;

  Future<SendPort>? _worker;
  Isolate? _isolate;
  final _pending = <int, Completer<Object?>>{};
  ReceivePort? _replies;
  int _next = 0;

  /// Path of [uri] relative to [root].
  String pathOf(Uri uri) {
    final r = root.pathSegments.where((s) => s.isNotEmpty).toList();
    final u = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.host.toLowerCase() != root.host.toLowerCase() ||
        u.length < r.length ||
        !_prefix(r, u)) {
      throw VirtualFileException(
        VirtualFileError.notFound,
        uri,
        'outside the source root',
      );
    }
    return u.sublist(r.length).join('/');
  }

  Uri uriOf(String path, {bool directory = false}) => root.replace(
    pathSegments: [
      ...root.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
      if (directory) '',
    ],
  );

  static bool _prefix(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<T> _call<T>(_Op op, List<Object?> args) async {
    final port = await (_worker ??= _spawn());
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    port.send((id, op, args));
    final r = await c.future;
    return r as T;
  }

  Future<SendPort> _spawn() async {
    final replies = ReceivePort();
    _replies = replies;
    final ready = Completer<SendPort>();
    replies.listen((m) {
      switch (m) {
        case final SendPort p:
          ready.complete(p);
        case (final int id, true, final Object? value):
          _pending.remove(id)?.complete(value);
        case (final int id, false, final Object error):
          _pending.remove(id)?.completeError(error);
        case [final Object? e, _]:
          final err = VirtualFileException(
            VirtualFileError.io,
            root,
            'worker crashed: $e',
          );
          for (final c in _pending.values) {
            c.completeError(err);
          }
          _pending.clear();
          _worker = null;
      }
    });
    _isolate = await Isolate.spawn(
      _workerMain,
      (replies.sendPort, _factory),
      debugName: debugName,
      onError: replies.sendPort,
    );
    return await ready.future;
  }

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final entries = await _call<List<VirtualEntry>>(_Op.list, [
      pathOf(directory),
    ]);
    for (final e in entries) {
      yield e;
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) => _call(_Op.stat, [pathOf(uri)]);

  @override
  Future<VirtualFile> open(Uri uri) async {
    final h = await _call<int>(_Op.open, [pathOf(uri), false, false]);
    final len = await _call<int?>(_Op.length, [h]);
    return _IsolateFile(this, uri, h, len);
  }

  @override
  Future<Uri> createDirectory(Uri parent, String name) async {
    _checkName(name);
    final p = _join(pathOf(parent), name);
    await _call<void>(_Op.mkdir, [p]);
    return uriOf(p, directory: true);
  }

  @override
  Future<Uri> rename(Uri uri, String newName) async {
    _checkName(newName);
    final from = pathOf(uri);
    final i = from.lastIndexOf('/');
    final to = i < 0 ? newName : '${from.substring(0, i)}/$newName';
    await _call<void>(_Op.rename, [from, to]);
    return uriOf(to, directory: uri.path.endsWith('/'));
  }

  @override
  Future<Uri> move(Uri uri, Uri directory) async {
    final from = pathOf(uri);
    final name = from.split('/').last;
    final to = _join(pathOf(directory), name);
    await _call<void>(_Op.rename, [from, to]);
    return uriOf(to, directory: uri.path.endsWith('/'));
  }

  @override
  Future<void> delete(Uri uri, {bool recursive = false}) async {
    final e = await stat(uri);
    if (!e.isDirectory) return await _call<void>(_Op.unlink, [pathOf(uri)]);
    if (recursive) {
      for (final c in await list(uri).toList()) {
        await delete(
          c.isDirectory
              ? uriOf(_join(pathOf(uri), c.name), directory: true)
              : uriOf(_join(pathOf(uri), c.name)),
          recursive: true,
        );
      }
    }
    await _call<void>(_Op.rmdir, [pathOf(uri)]);
  }

  /// Writes go to a hidden `.<name>.part` sibling, renamed on close, so
  /// readers and scanners never see partial uploads.
  @override
  Future<VirtualFileWriter> create(Uri uri) async {
    final target = pathOf(uri);
    final i = target.lastIndexOf('/');
    final part = i < 0
        ? '.$target.part'
        : '${target.substring(0, i)}/.${target.substring(i + 1)}.part';
    final h = await _call<int>(_Op.open, [part, true, true]);
    return _IsolateWriter(this, uri, h, part, target);
  }

  /// Ends the worker and its connection.
  Future<void> close() async {
    final w = _worker;
    if (w == null) return;
    try {
      await _call<void>(_Op.dispose, const []);
    } on Object {
      // Already gone.
    }
    _isolate?.kill();
    _replies?.close();
    _worker = null;
  }

  static String _join(String dir, String name) =>
      dir.isEmpty ? name : '$dir/$name';

  static void _checkName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\')) {
      throw ArgumentError.value(name, 'name', 'not a valid file name');
    }
  }
}

enum _Op {
  list,
  stat,
  open,
  length,
  read,
  write,
  close,
  mkdir,
  rename,
  unlink,
  rmdir,
  dispose,
}

void _workerMain((SendPort, SyncFileSystemFactory) args) {
  final (reply, factory) = args;
  final inbox = ReceivePort();
  SyncFileSystem? fs;
  Object? initError;
  try {
    fs = factory();
  } on Object catch (e) {
    initError = e;
  }
  reply.send(inbox.sendPort);
  inbox.listen((m) {
    final (id, op, a) = m as (int, _Op, List<Object?>);
    final f = fs;
    try {
      if (f == null) {
        final err = initError;
        if (err is VirtualFileException) throw err;
        throw StateError('file system failed to start: $err');
      }
      Object? result;
      switch (op) {
        case _Op.list:
          result = f.list(a[0]! as String);
        case _Op.stat:
          result = f.stat(a[0]! as String);
        case _Op.open:
          result = f.open(
            a[0]! as String,
            write: a[1]! as bool,
            create: a[2]! as bool,
          );
        case _Op.length:
          result = f.length(a[0]! as int);
        case _Op.read:
          result = f.read(a[0]! as int, a[1]! as int, a[2]! as int);
        case _Op.write:
          f.write(a[0]! as int, a[1]! as int, a[2]! as List<int>);
        case _Op.close:
          f.close(a[0]! as int);
        case _Op.mkdir:
          f.mkdir(a[0]! as String);
        case _Op.rename:
          f.rename(a[0]! as String, a[1]! as String);
        case _Op.unlink:
          f.unlink(a[0]! as String);
        case _Op.rmdir:
          f.rmdir(a[0]! as String);
        case _Op.dispose:
          f.dispose();
      }
      reply.send((id, true, result));
      if (op == _Op.dispose) inbox.close();
    } on VirtualFileException catch (e) {
      reply.send((id, false, e));
    } on Object catch (e) {
      reply.send((
        id,
        false,
        VirtualFileException(VirtualFileError.io, Uri(path: '$op'), '$e'),
      ));
    }
  });
}

final class _IsolateFile implements VirtualFile {
  _IsolateFile(this._fs, this.uri, this._handle, this._length);

  final IsolateFileSystem _fs;
  @override
  final Uri uri;
  final int _handle;
  final int? _length;
  bool _closed = false;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => _length;

  @override
  Future<Uint8List> read(int offset, int length) {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    RangeError.checkNotNegative(offset, 'offset');
    RangeError.checkNotNegative(length, 'length');
    return _fs._call<Uint8List>(_Op.read, [_handle, offset, length]);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _fs._call<void>(_Op.close, [_handle]);
  }
}

final class _IsolateWriter implements VirtualFileWriter {
  _IsolateWriter(this._fs, this.uri, this._handle, this._part, this._target);

  final IsolateFileSystem _fs;
  @override
  final Uri uri;
  final int _handle;
  final String _part;
  final String _target;
  int _offset = 0;

  @override
  Future<void> write(List<int> bytes) async {
    final at = _offset;
    _offset += bytes.length;
    await _fs._call<void>(_Op.write, [_handle, at, bytes]);
  }

  @override
  Future<void> close() async {
    await _fs._call<void>(_Op.close, [_handle]);
    try {
      await _fs._call<void>(_Op.unlink, [_target]);
    } on VirtualFileException catch (e) {
      if (e.error != VirtualFileError.notFound) rethrow;
    }
    await _fs._call<void>(_Op.rename, [_part, _target]);
  }

  @override
  Future<void> abort() async {
    await _fs._call<void>(_Op.close, [_handle]);
    await _fs._call<void>(_Op.unlink, [_part]);
  }
}
