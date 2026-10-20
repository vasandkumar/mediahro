import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Real files in a temp folder, read as buffers (the fake codec reads
/// buffers, never paths).
final class DiskIo implements ImageIo {
  DiskIo({this.failDelete = false});

  final MountedFileSystems mounts = MountedFileSystems();
  final List<Uri> writes = [];
  final List<Uri> deletes = [];

  /// Deleting always fails (a read-only source).
  bool failDelete;

  @override
  String? localPath(Uri uri) => null;

  @override
  Future<VirtualFile> open(Uri uri) => mounts.forUri(uri).open(uri);

  @override
  Future<void> replace(Uri uri, Uint8List bytes) async {
    writes.add(uri);
    File.fromUri(uri).writeAsBytesSync(bytes);
  }

  @override
  Future<void> create(Uri uri, Uint8List bytes) async {
    if (File.fromUri(uri).existsSync()) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    writes.add(uri);
    File.fromUri(uri).parent.createSync(recursive: true);
    File.fromUri(uri).writeAsBytesSync(bytes);
  }

  @override
  Future<bool> exists(Uri uri) async => File.fromUri(uri).existsSync();

  @override
  Future<void> delete(Uri uri) async {
    if (failDelete) {
      throw VirtualFileException(VirtualFileError.permissionDenied, uri);
    }
    deletes.add(uri);
    File.fromUri(uri).deleteSync();
  }
}

/// Photos at `dir/relPath`, opened through [io].
final class DiskFiles implements PhotoFileOpener {
  DiskFiles(this.dir, this.io);

  final Directory dir;
  final DiskIo io;

  @override
  Future<Uri> uriOf(PhotoEntry e) async => File('${dir.path}/${e.relPath}').uri;

  @override
  Future<ImageSource> open(PhotoEntry e) async => ImageSource(
    await io.open(await uriOf(e)),
    mtime: e.mtime,
    orientationHint: e.orientation,
  );
}
