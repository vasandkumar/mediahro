import 'dart:typed_data';

import 'package:mediahro/features/photos/archive/archive_book.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

final Uri testRoot = Uri(scheme: 'archive', path: '/book/');

/// An archive in memory, shaped like the isolate file system over libarchive:
/// entry paths below a root, folders implied by the paths.
final class FakeArchiveFs implements VirtualFileSystem {
  FakeArchiveFs(this.paths, {this.listError, this.encrypted = const {}});

  /// Entry paths of the files.
  final List<String> paths;

  /// Thrown by [list] when set.
  VirtualFileException? listError;

  /// Entries that cannot be opened without a passphrase.
  final Set<String> encrypted;

  final List<String> opened = [];
  int closedFiles = 0;

  @override
  Set<String> get schemes => const {'archive'};

  @override
  Set<VirtualFsCapability> get capabilities => const {VirtualFsCapability.list};

  List<String> _segments(Uri u) =>
      u.pathSegments.where((s) => s.isNotEmpty).toList();

  Uri _uri(List<String> segments, {required bool directory}) =>
      testRoot.replace(
        pathSegments: [..._segments(testRoot), ...segments, if (directory) ''],
      );

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final error = listError;
    if (error != null) throw error;
    final base = _segments(directory).skip(_segments(testRoot).length).toList();
    final seen = <String>{};
    for (final p in paths) {
      final parts = p.split('/');
      if (parts.length <= base.length) continue;
      var under = true;
      for (var i = 0; i < base.length; i++) {
        if (parts[i] != base[i]) under = false;
      }
      if (!under) continue;
      final name = parts[base.length];
      final isDir = parts.length > base.length + 1;
      if (!seen.add('$name/$isDir')) continue;
      yield VirtualEntry(
        uri: _uri([...base, name], directory: isDir),
        name: name,
        isDirectory: isDir,
        size: isDir ? null : 10,
      );
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async => throw UnimplementedError();

  @override
  Future<VirtualFile> open(Uri uri) async {
    final path = _segments(uri).skip(_segments(testRoot).length).join('/');
    if (!paths.contains(path)) {
      throw VirtualFileException(VirtualFileError.notFound, uri);
    }
    if (encrypted.contains(path)) {
      throw VirtualFileException(
        VirtualFileError.authenticationRequired,
        uri,
        'encrypted entry',
      );
    }
    opened.add(path);
    return _File(uri, () => closedFiles++);
  }
}

final class _File implements VirtualFile {
  _File(this.uri, this._onClose);

  @override
  final Uri uri;
  final void Function() _onClose;

  @override
  Future<int?> length() async => 3;

  @override
  Future<Uint8List> read(int offset, int length) async => Uint8List(0);

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async => _onClose();
}

/// Opens books over [FakeArchiveFs]; notes what it was asked.
final class FakeBooks implements ArchiveBooks {
  FakeBooks(this.make);

  /// Makes the file system for a try (the passphrase, if any, is given).
  final FakeArchiveFs Function(String? passphrase) make;

  final List<String?> passphrases = [];
  int closes = 0;
  FakeArchiveFs? last;

  @override
  Future<ArchiveBook> open(ArchiveRef ref, {String? passphrase}) async {
    passphrases.add(passphrase);
    final fs = make(passphrase);
    last = fs;
    return await ArchiveBook.open(
      name: ref.name,
      fs: fs,
      root: testRoot,
      onClose: () async => closes++,
      passphraseGiven: passphrase != null,
    );
  }
}
