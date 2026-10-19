import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A random-access, read-only view of a file on any source (docs/05 §9).
///
/// Every protocol client (local, SMB, NFS, WebDAV, FTP/SFTP, HTTP, archives,
/// cloud drives, server streams) exposes files through this interface so that
/// the playback engine can seek on every source via
/// `mpv_stream_cb_add_ro`, and parsers and the image pipeline can read
/// regions without downloading whole files.
///
/// Implementations must be safe to call from any isolate that owns them and
/// must never block the UI isolate.
abstract interface class VirtualFile {
  /// Canonical URI of the file, e.g. `smb://nas/share/film.mkv`.
  Uri get uri;

  /// Size in bytes, or `null` for unbounded streams (live HTTP, ICY radio).
  Future<int?> length();

  /// Reads up to [length] bytes starting at [offset].
  ///
  /// Returns fewer bytes only at end of file. Throws [VirtualFileException]
  /// on I/O failure.
  Future<Uint8List> read(int offset, int length);

  /// Whether [read] supports arbitrary offsets (false for pure streams).
  bool get isSeekable;

  /// Releases the underlying handle. Further reads throw.
  Future<void> close();
}

/// Metadata about an entry returned by [VirtualFileSystem.list] and
/// [VirtualFileSystem.stat].
@immutable
final class VirtualEntry {
  const VirtualEntry({
    required this.uri,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final Uri uri;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;

  @override
  bool operator ==(Object other) =>
      other is VirtualEntry &&
      other.uri == uri &&
      other.name == name &&
      other.isDirectory == isDirectory &&
      other.size == size &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(uri, name, isDirectory, size, modified);
}

/// Capabilities a file system may support beyond reading.
enum VirtualFsCapability {
  list,
  write,
  rename,
  delete,
  trash,
  watch,
  thumbnails,
}

/// A protocol-specific file system (one per mounted source).
abstract interface class VirtualFileSystem {
  /// URI schemes handled, e.g. `{'smb'}`.
  Set<String> get schemes;

  Set<VirtualFsCapability> get capabilities;

  Future<VirtualFile> open(Uri uri);

  Future<VirtualEntry> stat(Uri uri);

  /// Lists the direct children of a directory.
  Stream<VirtualEntry> list(Uri directory);
}

/// Sequential writer returned by [MutableFileSystem.create].
abstract interface class VirtualFileWriter {
  Uri get uri;
  Future<void> write(List<int> bytes);

  /// Commits the file. Implementations write to a temporary name and rename
  /// on close where the protocol allows, so readers never see partial files.
  Future<void> close();

  /// Drops a partial file.
  Future<void> abort();
}

/// A file system that can change (FILE-002, FILE-003, FILE-005, NET-018).
/// Capabilities in [VirtualFileSystem.capabilities] say which calls work.
abstract interface class MutableFileSystem implements VirtualFileSystem {
  Future<Uri> createDirectory(Uri parent, String name);

  /// Renames in place; throws [VirtualFileError.alreadyExists] on clashes.
  Future<Uri> rename(Uri uri, String newName);

  /// Moves into [directory] (same file system).
  Future<Uri> move(Uri uri, Uri directory);

  /// Permanent delete. User-facing deletes go to the OS trash first
  /// (StorageFacade.moveToTrash); this is for network shares without trash.
  Future<void> delete(Uri uri, {bool recursive = false});

  /// Creates or replaces [uri] for writing.
  Future<VirtualFileWriter> create(Uri uri);
}

/// Failure categories mapped to user-facing copy (docs/06 §8).
enum VirtualFileError {
  notFound,
  permissionDenied,
  authenticationRequired,
  unreachable,
  timeout,
  closed,
  io,
  unsupported,

  /// The target name is taken (rename/move/copy/create).
  alreadyExists,

  /// The server or disk is full.
  noSpace,

  /// The server presented an untrusted TLS certificate (docs/05 §9).
  untrustedCertificate,
}

final class VirtualFileException implements Exception {
  const VirtualFileException(this.error, this.uri, [this.detail]);

  final VirtualFileError error;
  final Uri uri;

  /// Technical detail for logs and the info sheet; never shown as primary copy.
  final String? detail;

  @override
  String toString() =>
      'VirtualFileException(${error.name}, $uri${detail == null ? '' : ', $detail'})';
}
