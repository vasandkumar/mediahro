import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/archive/archive_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/vfs/isolate_file_system.dart';
import 'package:mediahro_ffi/src/vfs/virtual_file.dart';
import 'package:meta/meta.dart';

/// Where an archive's bytes come from, inside the archive worker.
@immutable
sealed class ArchiveSource {
  const ArchiveSource();
}

/// A local file (fast path: libarchive reads it directly).
final class LocalArchiveSource extends ArchiveSource {
  const LocalArchiveSource(this.path);

  final String path;
}

/// A file on a blocking protocol client (SMB, NFS, FTP/SFTP) opened in the
/// same worker, so archives on network shares are browsed without copying.
final class SyncArchiveSource extends ArchiveSource {
  const SyncArchiveSource(this.fileSystem, this.path);

  final SyncFileSystemFactory fileSystem;
  final String path;
}

/// Zip-bomb and abuse limits (PRIV-005).
@immutable
final class ArchiveLimits {
  const ArchiveLimits({
    this.maxEntries = 100000,
    this.maxPathLength = 4096,
    this.maxEntryBytes = 64 << 30,
    this.memoryEntryBytes = 32 << 20,
    this.maxTotalBytes = 64 << 30,
    this.maxRatio = 1000,
    this.ratioFloorBytes = 256 << 20,
    this.maxPathDepth = 64,
  });

  final int maxEntries;
  final int maxPathLength;

  /// Entries larger than this (declared or actual) are refused.
  final int maxEntryBytes;

  /// Entries up to this size are decompressed once into memory on open;
  /// larger ones stream (forward reads; a backward seek restarts).
  final int memoryEntryBytes;

  /// All entries together may not unpack to more than this (the sizes the
  /// archive declares).
  final int maxTotalBytes;

  /// An archive may not unpack to more than this many times its own size...
  final int maxRatio;

  /// ...unless it unpacks to less than this in total (small files compress
  /// very well without being a bomb).
  final int ratioFloorBytes;

  /// Entries nested deeper than this many folders are ignored.
  final int maxPathDepth;
}

/// Why an archive that declares [unpackedBytes] in total and is
/// [packedBytes] long (null when unknown) is refused as a zip bomb, or null
/// when it is within [limits].
@visibleForTesting
String? archiveBombReason(
  int unpackedBytes,
  int? packedBytes,
  ArchiveLimits limits,
) {
  if (unpackedBytes > limits.maxTotalBytes) {
    return 'unpacks to more than the limit';
  }
  if (packedBytes != null &&
      unpackedBytes > limits.ratioFloorBytes &&
      unpackedBytes > packedBytes * limits.maxRatio) {
    return 'unpacks to far more than its size (compression ratio)';
  }
  return null;
}

final class _Entry {
  _Entry(
    this.path, {
    required this.size,
    required this.mtime,
    required this.index,
    this.encrypted = false,
  });

  final String path;
  final int? size;
  final int mtime;
  final int index;
  final bool encrypted;
}

typedef _ReadFn = ffi.IntPtr Function(
  ffi.Pointer<archive>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);
typedef _SeekFn = ffi.Int64 Function(
  ffi.Pointer<archive>,
  ffi.Pointer<ffi.Void>,
  ffi.Int64,
  ffi.Int,
);

const int _bufSize = 256 * 1024;

/// Read-only [SyncFileSystem] over one archive (FILE-004): ZIP/CBZ, RAR
/// and RAR5/CBR (libarchive's own reader), 7z/CB7, TAR (+gz/bz2/xz/zstd).
/// Paths are entry paths inside the archive.
final class ArchiveSyncFileSystem implements SyncFileSystem {
  ArchiveSyncFileSystem(
    this.source, {
    this.passphrase,
    this.limits = const ArchiveLimits(),
    ArchiveBindings? bindings,
    Uri? root,
  }) : _root = root ?? Uri(scheme: 'archive', path: '/'),
       _b =
           bindings ??
           ArchiveBindings(NativeLibraries.open(NativeLibrary.archive)) {
    final s = source;
    if (s is SyncArchiveSource) {
      final outer = s.fileSystem();
      _outer = outer;
      _outerHandle = outer.open(s.path);
      _outerSize = outer.length(_outerHandle);
    }
    _readCb = ffi.NativeCallable<_ReadFn>.isolateLocal(
      _onRead,
      exceptionalReturn: ARCHIVE_FATAL,
    );
    _seekCb = ffi.NativeCallable<_SeekFn>.isolateLocal(
      _onSeek,
      exceptionalReturn: ARCHIVE_FATAL,
    );
    try {
      _index();
    } on Object {
      // The constructor does not finish, so nobody else will free these.
      dispose();
      rethrow;
    }
  }

  final ArchiveSource source;
  final String? passphrase;
  final ArchiveLimits limits;
  final ArchiveBindings _b;

  /// Where this archive is mounted: the URIs of its entries are below it, so
  /// that a file system hosting it can map them back to paths
  /// (`IsolateFileSystem.pathOf`).
  final Uri _root;
  SyncFileSystem? _outer;
  int _outerHandle = 0;
  int? _outerSize;
  int _pos = 0;
  late final ffi.NativeCallable<_ReadFn> _readCb;
  late final ffi.NativeCallable<_SeekFn> _seekCb;
  late final ffi.Pointer<ffi.Uint8> _buf = calloc<ffi.Uint8>(_bufSize);

  final _entries = <String, _Entry>{};
  final _dirs = <String>{''};
  final _open = <int, _OpenEntry>{};
  int _next = 1;

  /// Number of file entries (tests and the archive info sheet).
  int get entryCount => _entries.length;

  Uri _uri(String path) => archiveEntryUri(_root, path);

  ffi.Pointer<archive> _openArchive() {
    final a = _b.archive_read_new();
    _b
      ..archive_read_support_filter_all(a)
      ..archive_read_support_format_all(a);
    final pass = passphrase;
    if (pass != null) {
      using(
        (m) => _b.archive_read_add_passphrase(
          a,
          pass.toNativeUtf8(allocator: m).cast(),
        ),
      );
    }
    final int rc;
    switch (source) {
      case LocalArchiveSource(:final path):
        rc = using(
          (m) => _b.archive_read_open_filename(
            a,
            path.toNativeUtf8(allocator: m).cast(),
            64 * 1024,
          ),
        );
      case SyncArchiveSource():
        _pos = 0;
        // archive_read_set_callback_data allocates the client dataset that
        // archive_read_open1 reads (dataset[0].data); without it open1
        // dereferences NULL+0x10. The callbacks use this object, not the
        // client pointer, so it stays null.
        _b
          ..archive_read_set_read_callback(a, _readCb.nativeFunction)
          ..archive_read_set_seek_callback(a, _seekCb.nativeFunction)
          ..archive_read_set_callback_data(a, ffi.nullptr);
        rc = _b.archive_read_open1(a);
    }
    if (rc != ARCHIVE_OK) {
      final msg = _error(a);
      _b.archive_read_free(a);
      throw VirtualFileException(
        VirtualFileError.unsupported,
        _uri(''),
        'not a readable archive: $msg',
      );
    }
    return a;
  }

  String _error(ffi.Pointer<archive> a) {
    final p = _b.archive_error_string(a);
    return p == ffi.nullptr ? '' : p.cast<Utf8>().toDartString();
  }

  int _onRead(
    ffi.Pointer<archive> a,
    ffi.Pointer<ffi.Void> data,
    ffi.Pointer<ffi.Pointer<ffi.Void>> out,
  ) {
    final bytes = _outer!.read(_outerHandle, _pos, _bufSize);
    _buf.asTypedList(bytes.length).setAll(0, bytes);
    _pos += bytes.length;
    out.value = _buf.cast();
    return bytes.length;
  }

  int _onSeek(
    ffi.Pointer<archive> a,
    ffi.Pointer<ffi.Void> data,
    int offset,
    int whence,
  ) {
    final size = _outerSize;
    final next = switch (whence) {
      0 => offset,
      1 => _pos + offset,
      _ => size == null ? -1 : size + offset,
    };
    if (next < 0) return ARCHIVE_FATAL;
    return _pos = next;
  }

  void _index() {
    final a = _openArchive();
    final entry = calloc<ffi.Pointer<archive_entry>>();
    try {
      var i = 0;
      var declared = 0;
      while (true) {
        final rc = _b.archive_read_next_header(a, entry);
        if (rc == ARCHIVE_EOF) break;
        if (rc < ARCHIVE_WARN) {
          throw VirtualFileException(VirtualFileError.io, _uri(''), _error(a));
        }
        if (i >= limits.maxEntries) {
          throw VirtualFileException(
            VirtualFileError.unsupported,
            _uri(''),
            'too many entries',
          );
        }
        declared += _record(entry.value, i);
        final early = archiveBombReason(declared, null, limits);
        if (early != null) {
          throw VirtualFileException(
            VirtualFileError.unsupported,
            _uri(''),
            early,
          );
        }
        _b.archive_read_data_skip(a);
        i++;
      }
      final bomb = archiveBombReason(declared, _packedBytes(), limits);
      if (bomb != null) {
        throw VirtualFileException(
          VirtualFileError.unsupported,
          _uri(''),
          bomb,
        );
      }
    } finally {
      calloc.free(entry);
      _b.archive_read_free(a);
    }
  }

  /// Notes one entry; returns the bytes it declares (0 for anything that is
  /// not a regular file: folders, links, devices are never followed).
  int _record(ffi.Pointer<archive_entry> e, int index) {
    final raw = _b.archive_entry_pathname_utf8(e);
    final name = (raw == ffi.nullptr ? _b.archive_entry_pathname(e) : raw)
        .cast<Utf8>()
        .toDartString();
    final path = normaliseEntryPath(name);
    if (path == null ||
        path.length > limits.maxPathLength ||
        '/'.allMatches(path).length >= limits.maxPathDepth) {
      return 0;
    }
    // Mask: mode_t is 16-bit on some ABIs; the type bits fit either way.
    final type = _b.archive_entry_filetype(e) & AE_IFMT;
    if (type == AE_IFDIR || name.endsWith('/')) {
      _addDirs(path, includeSelf: true);
      return 0;
    }
    if (type != AE_IFREG && type != 0) return 0;
    // A hard link names another entry; it is not a file of its own.
    if (_b.archive_entry_hardlink(e) != ffi.nullptr) return 0;
    // A file that does not say how big it is cannot be held to a limit.
    if (_b.archive_entry_size_is_set(e) == 0) return 0;
    final size = _b.archive_entry_size(e);
    if (size < 0) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        _uri(''),
        'an entry declares a negative size',
      );
    }
    _addDirs(path, includeSelf: false);
    _entries[path] = _Entry(
      path,
      size: size,
      mtime: _b.archive_entry_mtime(e),
      index: index,
      encrypted: _b.archive_entry_is_encrypted(e) != 0,
    );
    return size;
  }

  /// The length of the archive file itself, when known.
  int? _packedBytes() {
    switch (source) {
      case LocalArchiveSource(:final path):
        try {
          return File(path).lengthSync();
        } on Object {
          return null;
        }
      case SyncArchiveSource():
        return _outerSize;
    }
  }

  void _addDirs(String path, {required bool includeSelf}) {
    final parts = path.split('/');
    final n = parts.length + (includeSelf ? 1 : 0);
    for (var i = 1; i < n; i++) {
      _dirs.add(parts.sublist(0, i).join('/'));
    }
  }

  @override
  List<VirtualEntry> list(String path) {
    if (!_dirs.contains(path)) {
      throw VirtualFileException(VirtualFileError.notFound, _uri(path));
    }
    final prefix = path.isEmpty ? '' : '$path/';
    bool direct(String p) =>
        p.startsWith(prefix) &&
        p != path &&
        !p.substring(prefix.length).contains('/');
    final out = <VirtualEntry>[];
    for (final d in _dirs.where(direct)) {
      out.add(
        VirtualEntry(
          uri: _uri('$d/'),
          name: d.substring(prefix.length),
          isDirectory: true,
        ),
      );
    }
    for (final e in _entries.values.where((e) => direct(e.path))) {
      out.add(
        VirtualEntry(
          uri: _uri(e.path),
          name: e.path.substring(prefix.length),
          isDirectory: false,
          size: e.size,
          modified: e.mtime == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  e.mtime * 1000,
                  isUtc: true,
                ),
        ),
      );
    }
    return out;
  }

  @override
  VirtualEntry stat(String path) {
    if (_dirs.contains(path)) {
      return VirtualEntry(
        uri: _uri('$path/'),
        name: path.split('/').last,
        isDirectory: true,
      );
    }
    final e = _entries[path];
    if (e == null) {
      throw VirtualFileException(VirtualFileError.notFound, _uri(path));
    }
    return VirtualEntry(
      uri: _uri(path),
      name: path.split('/').last,
      isDirectory: false,
      size: e.size,
    );
  }

  @override
  int open(String path, {bool write = false, bool create = false}) {
    if (write) _readOnly();
    final e = _entries[path];
    if (e == null) {
      throw VirtualFileException(VirtualFileError.notFound, _uri(path));
    }
    if (e.encrypted && passphrase == null) {
      throw VirtualFileException(
        VirtualFileError.authenticationRequired,
        _uri(path),
        'encrypted entry',
      );
    }
    if ((e.size ?? 0) > limits.maxEntryBytes) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        _uri(path),
        'entry too large',
      );
    }
    final h = _OpenEntry(e);
    final size = e.size;
    if (size != null && size <= limits.memoryEntryBytes) {
      h.memory = _readAll(e, size);
    }
    final id = _next++;
    _open[id] = h;
    return id;
  }

  @override
  int? length(int handle) {
    final h = _open[handle];
    return h?.memory?.length ?? h?.entry.size;
  }

  @override
  Uint8List read(int handle, int offset, int length) {
    final h = _open[handle];
    if (h == null) {
      throw VirtualFileException(VirtualFileError.closed, _uri(''));
    }
    final mem = h.memory;
    if (mem != null) {
      if (offset >= mem.length) return Uint8List(0);
      final end = offset + length > mem.length ? mem.length : offset + length;
      return Uint8List.sublistView(mem, offset, end);
    }
    // Streaming: restart when seeking backwards, skip forward otherwise.
    if (h.reader == null || offset < h.cursor) _seekTo(h);
    while (h.cursor < offset) {
      final gap = offset - h.cursor;
      if (_readData(h, gap < _bufSize ? gap : _bufSize) == 0) {
        return Uint8List(0);
      }
    }
    final out = BytesBuilder(copy: false);
    while (out.length < length) {
      final want = length - out.length;
      final n = _readData(h, want < _bufSize ? want : _bufSize);
      if (n == 0) break;
      out.add(Uint8List.fromList(_buf.asTypedList(n)));
    }
    return out.takeBytes();
  }

  void _seekTo(_OpenEntry h) {
    final old = h.reader;
    if (old != null) _b.archive_read_free(old);
    final a = _openArchive();
    final entry = calloc<ffi.Pointer<archive_entry>>();
    try {
      for (var i = 0; i <= h.entry.index; i++) {
        final rc = _b.archive_read_next_header(a, entry);
        if (rc != ARCHIVE_OK && rc != ARCHIVE_WARN) {
          throw VirtualFileException(
            VirtualFileError.io,
            _uri(h.entry.path),
            _error(a),
          );
        }
        if (i < h.entry.index) _b.archive_read_data_skip(a);
      }
    } finally {
      calloc.free(entry);
    }
    h
      ..reader = a
      ..cursor = 0;
  }

  int _readData(_OpenEntry h, int max) {
    final reader = h.reader!;
    final n = _b.archive_read_data(reader, _buf.cast(), max);
    if (n < 0) {
      throw VirtualFileException(
        VirtualFileError.io,
        _uri(h.entry.path),
        _error(reader),
      );
    }
    h.cursor += n;
    final declared = h.entry.size;
    if (declared != null && h.cursor > declared + _bufSize) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        _uri(h.entry.path),
        'entry larger than declared',
      );
    }
    if (h.cursor > limits.maxEntryBytes) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        _uri(h.entry.path),
        'entry exceeds its limit',
      );
    }
    return n;
  }

  Uint8List _readAll(_Entry e, int declared) {
    final h = _OpenEntry(e);
    _seekTo(h);
    try {
      final out = BytesBuilder(copy: false);
      while (true) {
        final n = _readData(h, _bufSize);
        if (n == 0) break;
        out.add(Uint8List.fromList(_buf.asTypedList(n)));
        // A size lie (zip bomb) stops at the declared size + one buffer.
        if (out.length > declared + _bufSize) {
          throw VirtualFileException(
            VirtualFileError.unsupported,
            _uri(e.path),
            'entry larger than declared',
          );
        }
      }
      return out.takeBytes();
    } finally {
      _b.archive_read_free(h.reader!);
    }
  }

  @override
  void close(int handle) {
    final reader = _open.remove(handle)?.reader;
    if (reader != null) _b.archive_read_free(reader);
  }

  @override
  void write(int handle, int offset, List<int> bytes) => _readOnly();
  @override
  void mkdir(String path) => _readOnly();
  @override
  void rename(String from, String to) => _readOnly();
  @override
  void unlink(String path) => _readOnly();
  @override
  void rmdir(String path) => _readOnly();

  Never _readOnly() => throw VirtualFileException(
    VirtualFileError.unsupported,
    _uri(''),
    'archives are read-only',
  );

  @override
  void dispose() {
    _open.keys.toList().forEach(close);
    final o = _outer;
    if (o != null) {
      o
        ..close(_outerHandle)
        ..dispose();
    }
    _readCb.close();
    _seekCb.close();
    calloc.free(_buf);
  }
}

final class _OpenEntry {
  _OpenEntry(this.entry);

  final _Entry entry;
  Uint8List? memory;
  ffi.Pointer<archive>? reader;
  int cursor = 0;
}

final RegExp _drive = RegExp('^[A-Za-z]:');

/// Normalises an archive entry name: `/`-separated, no leading `./`, no
/// `..` escapes, no absolute names (returns null for unsafe names).
String? normaliseEntryPath(String name) {
  final slashed = name.replaceAll(r'\', '/');
  // Absolute names (a root, a drive, a home) are ignored, not made relative.
  if (slashed.startsWith('/') ||
      slashed.startsWith('~') ||
      _drive.hasMatch(slashed)) {
    return null;
  }
  final parts = <String>[];
  for (final p in slashed.split('/')) {
    if (p.isEmpty || p == '.') continue;
    if (p == '..') return null;
    parts.add(p);
  }
  return parts.isEmpty ? null : parts.join('/');
}

/// The URI of [path] (`''` for the archive itself, `dir/` for a folder) below
/// [root], the mount point of an archive file system. Entries must be listed
/// with URIs under the root, or a folder found in a listing cannot be listed
/// in turn: `IsolateFileSystem.pathOf` refuses anything outside the root.
Uri archiveEntryUri(Uri root, String path) {
  final base = root.path.isEmpty
      ? '/'
      : (root.path.endsWith('/') ? root.path : '${root.path}/');
  return root.replace(path: '$base$path');
}

/// An archive browsed as a file system (`archive:///path?src=<outer uri>`).
IsolateFileSystem archiveFileSystem(
  Uri root,
  ArchiveSource source, {
  String? passphrase,
  ArchiveLimits limits = const ArchiveLimits(),
}) => IsolateFileSystem(
  root: root,
  schemes: const {'archive'},
  capabilities: const {VirtualFsCapability.list},
  debugName: 'mediahro-archive',
  factory: () => ArchiveSyncFileSystem(
    source,
    passphrase: passphrase,
    limits: limits,
    root: root,
  ),
);
