import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';

/// Saves metadata edits; faked in tests.
abstract interface class MetadataEditor {
  Future<MetadataWriteOutcome> save(PhotoEntry entry, ImageMetadataEdit edit);
}

/// Saves metadata edits (IMG-006): writes them into the file (or an XMP
/// sidecar for RAW and formats that cannot hold them), then re-reads the
/// file so the timeline shows the new capture time and title.
final class MetadataEditService implements MetadataEditor {
  MetadataEditService({
    required this.files,
    required this.pipeline,
    required this.prober,
    required this.db,
  });

  final PhotoFileOpener files;
  final MediahroImagePipeline pipeline;
  final ImageProber prober;
  final LibraryDatabase db;

  @override
  Future<MetadataWriteOutcome> save(
    PhotoEntry entry,
    ImageMetadataEdit edit,
  ) async {
    final src = await files.open(entry);
    final MetadataWriteOutcome outcome;
    try {
      outcome = await pipeline.applyMetadataEdit(src, edit);
    } finally {
      await src.file.close();
    }
    // A written file has a new size and time; a sidecar changes neither, but
    // the capture time may have: re-read either way.
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
    return outcome;
  }
}
