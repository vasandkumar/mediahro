import 'dart:typed_data';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// A part of another file as a file of its own: the Motion Photo video that
/// sits at the end of a JPEG, played without copying it out. Reads are
/// shifted by [offset] and stop at [size]; closing closes the file under it.
final class RangeFile implements VirtualFile {
  RangeFile(this.inner, {required this.offset, required this.size});

  final VirtualFile inner;
  final int offset;
  final int size;

  @override
  Uri get uri => inner.uri.replace(fragment: 'range=$offset+$size');

  @override
  Future<int?> length() async => size;

  @override
  bool get isSeekable => inner.isSeekable;

  @override
  Future<Uint8List> read(int at, int length) async {
    if (at < 0 || length < 0) throw RangeError('negative');
    if (at >= size || length == 0) return Uint8List(0);
    final n = length < size - at ? length : size - at;
    return await inner.read(offset + at, n);
  }

  @override
  Future<void> close() => inner.close();
}

/// The short video that goes with a photo (IMG-001): the MOV beside a Live
/// Photo, or the MP4 inside a Motion Photo. The caller closes [file].
final class PhotoClip {
  const PhotoClip(this.file, {required this.motion});

  final VirtualFile file;

  /// True for a Motion Photo (video inside the image file), false for a Live
  /// Photo (video in its own file).
  final bool motion;
}

/// Finds the clip of a photo; faked in widget tests.
abstract interface class PhotoClips {
  /// The clip of [entry], or null when it has none that can be read.
  Future<PhotoClip?> open(PhotoEntry entry);
}

/// Opens clips through the same files the library reads photos from.
final class PhotoClipService implements PhotoClips {
  PhotoClipService({
    required this.files,
    required this.io,
    required this.pipeline,
    required this.db,
  });

  final PhotoFileOpener files;
  final ImageIo io;
  final MediahroImagePipeline pipeline;
  final LibraryDatabase db;

  @override
  Future<PhotoClip?> open(PhotoEntry entry) async {
    try {
      if (entry.motionPhoto) return await _motion(entry);
      if (entry.livePhoto) return await _live(entry);
    } on Object {
      // A clip that cannot be read leaves the still as it is.
    }
    return null;
  }

  Future<PhotoClip?> _motion(PhotoEntry entry) async {
    final src = await files.open(entry);
    try {
      final parsed = await pipeline.parsedMetadata(src);
      final length = parsed.motionVideoLength;
      final total = await src.file.length();
      // The video must fit inside the file and leave room for the picture.
      if (length == null || total == null || length <= 0 || length >= total) {
        await src.file.close();
        return null;
      }
      return PhotoClip(
        RangeFile(src.file, offset: total - length, size: length),
        motion: true,
      );
    } on Object {
      await src.file.close();
      rethrow;
    }
  }

  Future<PhotoClip?> _live(PhotoEntry entry) async {
    final row = await (db.select(
      db.imageMeta,
    )..where((m) => m.itemId.equals(entry.id))).getSingleOrNull();
    final name = row?.pairedVideoPath;
    if (name == null || name.isEmpty || name.contains('/')) return null;
    final image = await files.uriOf(entry);
    final segs = [...image.pathSegments]..removeLast();
    final video = image.replace(pathSegments: [...segs, name]);
    return PhotoClip(await io.open(video), motion: false);
  }
}
