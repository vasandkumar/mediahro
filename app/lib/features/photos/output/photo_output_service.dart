import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/features/photos/edit/photo_editor_service.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/platform/imaging.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:meta/meta.dart';

/// What happens to a photo on its way out (IMG-015, IMG-006 "strip on
/// share").
@immutable
final class ShareOptions {
  const ShareOptions({this.maxEdge, this.stripMetadata = false});

  /// Longest side in pixels; null sends the original size.
  final int? maxEdge;

  /// Leave out location, camera and dates.
  final bool stripMetadata;

  bool get isPlain => maxEdge == null && !stripMetadata;
}

/// Share, set as wallpaper, print and copy (IMG-015). Faked in widget tests.
abstract interface class PhotoOutput {
  /// What the OS offers here (wallpaper targets, printing).
  Future<ImagingSupport> support();

  Future<void> share(List<PhotoEntry> photos, ShareOptions options);

  Future<void> setWallpaper(PhotoEntry photo, WallpaperTarget target);

  /// False when the user cancelled the print dialog.
  Future<bool> print(List<PhotoEntry> photos, PrintLayout layout);

  Future<void> copy(PhotoEntry photo);
}

final class PhotoOutputService implements PhotoOutput {
  PhotoOutputService({
    required this.files,
    required this.pipeline,
    required this.imaging,
    required this.storage,
    required this.staging,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PhotoFileOpener files;
  final MediahroImagePipeline pipeline;
  final ImagingFacade imaging;
  final StorageFacade storage;

  /// Where copies made for sharing live until they are cleaned up.
  final Directory staging;
  final DateTime Function() _clock;

  /// How long a staged copy is kept; the receiving app has long since read
  /// it.
  static const Duration keepStaged = Duration(hours: 2);

  @override
  Future<ImagingSupport> support() => imaging.support();

  /// Deletes staged copies older than [keepStaged].
  Future<void> cleanStaging() async {
    if (!staging.existsSync()) return;
    final cutoff = _clock().subtract(keepStaged);
    for (final e in staging.listSync()) {
      try {
        if (e.statSync().modified.isBefore(cutoff)) {
          e.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // Gone already, or in use: next time.
      }
    }
  }

  /// A folder for the files of one operation.
  Future<Directory> _fresh() async {
    await cleanStaging();
    final d = Directory(
      '${staging.path}${Platform.pathSeparator}${_clock().microsecondsSinceEpoch}',
    );
    await d.create(recursive: true);
    return d;
  }

  /// [photo] as a `file:` URI the OS can read: its own file when it is a
  /// plain local file, a staged copy otherwise (device library, network).
  Future<Uri> _readable(PhotoEntry photo, Directory into) async {
    final uri = await files.uriOf(photo);
    if (uri.scheme == 'file') return uri;
    final src = await files.open(photo);
    try {
      final out = File('${into.path}${Platform.pathSeparator}${photo.name}');
      final sink = out.openWrite();
      try {
        final length = await src.file.length() ?? 0;
        for (var at = 0; at < length; at += 1 << 20) {
          final n = (length - at).clamp(0, 1 << 20);
          sink.add(await src.file.read(at, n));
        }
      } finally {
        await sink.close();
      }
      return out.uri;
    } finally {
      await src.file.close();
    }
  }

  /// The file to send for [photo] under [o], as a `file:` URI.
  Future<Uri> _prepared(
    PhotoEntry photo,
    ShareOptions o,
    Directory into,
  ) async {
    if (o.isPlain || photo.isVideo) return await _readable(photo, into);
    final src = await files.open(photo);
    try {
      final format = editFormatFor(photo.ext);
      var name = photo.name;
      Uint8List? bytes;
      if (o.maxEdge == null && o.stripMetadata) {
        // No re-encoding: only the metadata goes.
        bytes = await pipeline.tryStrippedBytes(src);
      }
      if (bytes == null) {
        bytes = await pipeline.renderEdited(
          src,
          EditRecipe.none,
          EncodeOptions(
            format: format,
            maxEdge: o.maxEdge,
            stripMetadata: o.stripMetadata,
          ),
        );
        name = _renamed(name, format);
      }
      final out = File('${into.path}${Platform.pathSeparator}$name');
      await out.writeAsBytes(bytes, flush: true);
      return out.uri;
    } finally {
      await src.file.close();
    }
  }

  String _renamed(String name, EncodeFormat f) {
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    return '$stem.${extensionOf(f)}';
  }

  @override
  Future<void> share(List<PhotoEntry> photos, ShareOptions options) async {
    final dir = await _fresh();
    final uris = <Uri>[];
    for (final p in photos) {
      uris.add(await _prepared(p, options, dir));
    }
    await storage.share(uris);
  }

  @override
  Future<void> setWallpaper(PhotoEntry photo, WallpaperTarget target) async {
    final dir = await _fresh();
    await imaging.setWallpaper(await _readable(photo, dir), target);
  }

  @override
  Future<bool> print(List<PhotoEntry> photos, PrintLayout layout) async {
    final dir = await _fresh();
    return await imaging.printImages([
      for (final p in photos) await _readable(p, dir),
    ], layout);
  }

  @override
  Future<void> copy(PhotoEntry photo) async {
    final dir = await _fresh();
    await imaging.copyImage(await _readable(photo, dir));
  }
}
