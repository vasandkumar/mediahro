import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mediahro/features/photos/archive/comic_order.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// An archive the user picked (a ZIP, CBZ, RAR, CBR, 7z or CB7) (IMG-017).
final class ArchiveRef {
  const ArchiveRef({required this.uri, required this.name});

  /// A `file:` URI, or a `content:` URI that Android handed out.
  final Uri uri;
  final String name;

  /// Tells the library, the history and the saved page which book this is.
  String get key => '$uri';
}

/// A reason an archive could not be opened as a book.
enum ArchiveProblem {
  /// Not an archive libarchive reads, or damaged.
  unreadable,

  /// It holds no pictures.
  noPages,

  /// Pages are encrypted and need a passphrase.
  needsPassphrase,
}

final class ArchiveBookException implements Exception {
  const ArchiveBookException(this.problem);

  final ArchiveProblem problem;

  @override
  String toString() => 'ArchiveBookException($problem)';
}

/// The pictures of one archive, in reading order, opened one at a time
/// without unpacking the archive (IMG-017, FILE-004).
final class ArchiveBook {
  ArchiveBook._(this.name, this._fs, this._root, this.paths, this._onClose);

  /// Opens [fs] (the archive as a file system rooted at [root]) as a book.
  /// Throws [ArchiveBookException] when there is nothing to read.
  static Future<ArchiveBook> open({
    required String name,
    required VirtualFileSystem fs,
    required Uri root,
    Future<void> Function()? onClose,
  }) async {
    final found = <String>[];
    final pending = <Uri>[root];
    final prefix = root.pathSegments.where((s) => s.isNotEmpty).length;
    try {
      while (pending.isNotEmpty) {
        final dir = pending.removeLast();
        await for (final e in fs.list(dir)) {
          if (e.isDirectory) {
            pending.add(e.uri);
          } else {
            final segments = e.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .skip(prefix)
                .toList();
            found.add(segments.join('/'));
          }
        }
      }
    } on VirtualFileException catch (e) {
      await onClose?.call();
      if (e.error == VirtualFileError.authenticationRequired) {
        throw const ArchiveBookException(ArchiveProblem.needsPassphrase);
      }
      throw const ArchiveBookException(ArchiveProblem.unreadable);
    } on Object {
      await onClose?.call();
      rethrow;
    }
    final pages = orderedPages(found);
    if (pages.isEmpty) {
      await onClose?.call();
      throw const ArchiveBookException(ArchiveProblem.noPages);
    }
    return ArchiveBook._(name, fs, root, pages, onClose);
  }

  final String name;
  final VirtualFileSystem _fs;
  final Uri _root;
  final Future<void> Function()? _onClose;

  /// Entry paths of the pages, in reading order.
  final List<String> paths;
  bool _closed = false;

  int get pageCount => paths.length;

  /// The file name of page [index], without its folders.
  String pageName(int index) => paths[index].split('/').last;

  Uri _uriOf(String path) => _root.replace(
    pathSegments: [
      ..._root.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/'),
    ],
  );

  /// Opens page [index] for reading; the caller closes the file. An
  /// encrypted page throws [ArchiveBookException] with
  /// [ArchiveProblem.needsPassphrase].
  Future<VirtualFile> openPage(int index) async {
    if (_closed) {
      throw VirtualFileException(VirtualFileError.closed, _root);
    }
    try {
      return await _fs.open(_uriOf(paths[index]));
    } on VirtualFileException catch (e) {
      if (e.error == VirtualFileError.authenticationRequired) {
        throw const ArchiveBookException(ArchiveProblem.needsPassphrase);
      }
      rethrow;
    }
  }

  /// Lets go of the archive (its worker and any file it holds).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _onClose?.call();
  }
}

/// Opens archives as books; tests replace it.
abstract interface class ArchiveBooks {
  Future<ArchiveBook> open(ArchiveRef ref, {String? passphrase});
}

/// Opens archives with libarchive on a worker isolate (`archiveFileSystem`).
/// Android hands out `content://` documents; those are read through a
/// detached fd that stays open while the book does, as `/proc/self/fd/N`.
final class FfiArchiveBooks implements ArchiveBooks {
  FfiArchiveBooks(this._storage, {FdIo? io}) : _io = io ?? PosixFdIo();

  final StorageFacade _storage;
  final FdIo _io;

  @override
  Future<ArchiveBook> open(ArchiveRef ref, {String? passphrase}) async {
    int? fd;
    final String path;
    if (ref.uri.scheme == 'content') {
      fd = await _storage.openDocumentFd(ref.uri);
      path = '/proc/self/fd/$fd';
    } else {
      path = ref.uri.toFilePath();
    }
    final root = Uri(scheme: 'archive', path: '/${_id(ref.key)}/');
    final fs = archiveFileSystem(
      root,
      LocalArchiveSource(path),
      passphrase: passphrase,
    );
    var released = false;
    Future<void> release() async {
      if (released) return;
      released = true;
      try {
        await fs.close();
      } finally {
        if (fd != null) _io.close(fd);
      }
    }

    // The book releases the archive itself when it cannot be opened.
    return await ArchiveBook.open(
      name: ref.name,
      fs: fs,
      root: root,
      onClose: release,
    );
  }

  static String _id(String key) =>
      sha256.convert(utf8.encode(key)).toString().substring(0, 16);
}
