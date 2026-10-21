import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/edit/edit_store.dart';
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';
import 'package:mediahro/images/pipeline/pixel_ops.dart';

/// Longest edge of the picture previews are computed on. A phone screen is
/// about this wide, and the render time follows the pixel count (the preview
/// budget is 400 ms on the reference phone).
const int editPreviewEdge = 1080;

/// What the editor needs from the library and the image pipeline; faked in
/// widget tests.
abstract interface class PhotoEditor {
  /// A reduced copy of [entry] (longest edge at most [edge]) that previews
  /// are computed on.
  Future<PixelFrame> loadProxy(PhotoEntry entry, {int edge = editPreviewEdge});

  /// [proxy] with [recipe] applied.
  Future<PixelFrame> render(PixelFrame proxy, EditRecipe recipe);

  /// The unsaved edit left from last time, or none.
  Future<EditRecipe> savedRecipe(PhotoEntry entry);

  Future<void> storeRecipe(PhotoEntry entry, EditRecipe recipe);

  /// Whether the original can be replaced (a format this app can write).
  bool canReplace(PhotoEntry entry);

  /// Writes the edited photo next to the original under a new name; returns
  /// that name.
  Future<String> saveCopy(PhotoEntry entry, EditRecipe recipe);

  /// Rewrites the original with the edit applied.
  Future<void> replaceOriginal(PhotoEntry entry, EditRecipe recipe);
}

/// The format an edited copy of a [ext] file is written in: the same when the
/// app can write it, JPEG otherwise (HEIC, AVIF, RAW, TIFF, ...).
EncodeFormat editFormatFor(String ext) => switch (ext.toLowerCase()) {
  'png' => EncodeFormat.png,
  'webp' => EncodeFormat.webp,
  'jxl' => EncodeFormat.jxl,
  _ => EncodeFormat.jpeg,
};

String extensionOf(EncodeFormat f) => switch (f) {
  EncodeFormat.jpeg => 'jpg',
  EncodeFormat.png => 'png',
  EncodeFormat.webp => 'webp',
  EncodeFormat.jxl => 'jxl',
  EncodeFormat.avif => 'avif',
  EncodeFormat.heic => 'heic',
};

/// Formats whose original is rewritten in place without changing its kind.
const _replaceable = {'jpg', 'jpeg', 'png', 'webp', 'jxl'};

final class PhotoEditService implements PhotoEditor {
  PhotoEditService({
    required this.files,
    required this.pipeline,
    required this.io,
    required this.prober,
    required this.db,
    required this.store,
  });

  final PhotoFileOpener files;
  final MediahroImagePipeline pipeline;
  final ImageIo io;
  final ImageProber prober;
  final LibraryDatabase db;
  final EditStore store;

  /// JPEG and WebP quality of edited photos.
  static const int quality = 92;

  @override
  Future<PixelFrame> loadProxy(
    PhotoEntry entry, {
    int edge = editPreviewEdge,
  }) async {
    final src = await files.open(entry);
    try {
      final info = await pipeline.info(src);
      final longest = math.max(info.width, info.height);
      final scale = longest <= edge ? 1.0 : edge / longest;
      final d = await pipeline.decode(src, scale: scale);
      final frame = PixelFrame(
        width: d.width,
        height: d.height,
        rgba: d.pixels,
      );
      return math.max(frame.width, frame.height) > edge
          ? downscaleToEdge(frame, edge)
          : frame;
    } finally {
      await src.file.close();
    }
  }

  @override
  Future<PixelFrame> render(PixelFrame proxy, EditRecipe recipe) =>
      pipeline.editFrame(proxy, recipe);

  @override
  Future<EditRecipe> savedRecipe(PhotoEntry entry) => store.load(entry.id);

  @override
  Future<void> storeRecipe(PhotoEntry entry, EditRecipe recipe) =>
      store.save(entry.id, recipe);

  @override
  bool canReplace(PhotoEntry entry) => _replaceable.contains(entry.ext);

  @override
  Future<String> saveCopy(PhotoEntry entry, EditRecipe recipe) async {
    final format = editFormatFor(entry.ext);
    final bytes = await _render(entry, recipe, format);
    final original = await files.uriOf(entry);
    final segments = [...original.pathSegments];
    final name = Uri.decodeComponent(segments.removeLast());
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final ext = extensionOf(format);
    for (var n = 1; ; n++) {
      final candidate = n == 1
          ? '${stem}_edited.$ext'
          : '${stem}_edited_$n.$ext';
      final target = original.replace(pathSegments: [...segments, candidate]);
      if (await io.exists(target)) continue;
      await io.create(target, bytes);
      return candidate;
    }
  }

  @override
  Future<void> replaceOriginal(PhotoEntry entry, EditRecipe recipe) async {
    if (!canReplace(entry)) {
      throw UnsupportedError('${entry.ext} files are saved as a copy.');
    }
    final bytes = await _render(entry, recipe, editFormatFor(entry.ext));
    await io.replace(await files.uriOf(entry), bytes);
    await store.delete(entry.id);
    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(entry.id))).getSingleOrNull();
    if (item != null) {
      final fresh = await files.open(entry);
      try {
        await prober.reprobe(item, fresh.file);
      } finally {
        await fresh.file.close();
      }
    }
  }

  Future<Uint8List> _render(
    PhotoEntry entry,
    EditRecipe recipe,
    EncodeFormat format,
  ) async {
    final src = await files.open(entry);
    try {
      return await pipeline.renderEdited(
        src,
        recipe,
        EncodeOptions(format: format, quality: quality),
      );
    } finally {
      await src.file.close();
    }
  }
}

/// How a batch of edits went.
typedef BatchOutcome = ({int saved, int failed});

/// Applies the light, colour, detail and curves of [look] to every photo in
/// [photos] (IMG-009 batch apply), one at a time so a bad file does not stop
/// the rest. Each result is a new file next to its original, or, when
/// [replace] is true, the original rewritten (only for formats that allow
/// it; others get a copy). Videos are skipped. [onProgress] gets the number
/// done so far.
Future<BatchOutcome> applyLookToPhotos(
  PhotoEditor editor,
  List<PhotoEntry> photos,
  EditRecipe look, {
  bool replace = false,
  void Function(int done)? onProgress,
}) async {
  final recipe = look.look();
  var saved = 0;
  var failed = 0;
  var done = 0;
  for (final p in photos) {
    if (p.isVideo) continue;
    try {
      if (replace && editor.canReplace(p)) {
        await editor.replaceOriginal(p, recipe);
      } else {
        await editor.saveCopy(p, recipe);
      }
      saved++;
    } on Object {
      failed++;
    }
    onProgress?.call(++done);
  }
  return (saved: saved, failed: failed);
}
