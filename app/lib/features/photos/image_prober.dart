import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/core/scanner/probe_queue.dart';
import 'package:mediahro/features/photos/map/place_resolver.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Reads the facts of image items for the library (docs/05 §6, IMG-003,
/// IMG-005): size, capture time, camera, GPS, orientation, Live Photo pair
/// and the Motion Photo / HDR markers. Plugged into the probe queue for
/// `ItemKind.image` (the engine's prober handles audio and video).
///
/// Image-specific columns go to `image_meta`; the rest is returned for the
/// index writer. A Motion Photo is recorded as an embedded `mp4` video codec
/// and a gain-map still as `gainmap` HDR, so the timeline can badge both
/// without new columns.
final class ImageProber implements MediaProber {
  ImageProber({
    required this.pipeline,
    required this.db,
    required this.io,
    TagRepository? tags,
    this.places,
  }) : tags = tags ?? TagRepository(db);

  final MediahroImagePipeline pipeline;
  final LibraryDatabase db;
  final ImageIo io;
  final TagRepository tags;

  /// Names the place of a geotagged photo (IMG-007); none in tests that do
  /// not care.
  final PlaceResolver? places;

  static const _videoPairExtensions = ['mov', 'MOV', 'mp4', 'MP4'];

  @override
  Future<ProbeResult> probe(VirtualFile file, ItemRow item) async {
    if (item.kind != ItemKind.image) {
      throw ArgumentError.value(item.kind, 'item.kind', 'images only');
    }
    final src = ImageSource(file, mtime: item.mtime);
    final facts = await pipeline.readFacts(src);
    final info = facts.info;
    final m = facts.parsed.metadata;
    final pair = facts.parsed.livePhotoId == null
        ? null
        : await _pairedVideo(file.uri);
    final placeId = await places?.resolve(m.latitude, m.longitude);
    final camera = [
      m.cameraMake,
      m.cameraModel,
    ].whereType<String>().join(' ').trim();
    await db
        .into(db.imageMeta)
        .insertOnConflictUpdate(
          ImageMetaCompanion.insert(
            itemId: Value(item.id),
            camera: Value(camera.isEmpty ? null : camera),
            lens: Value(m.lens),
            orientation: Value(facts.parsed.orientation),
            latitude: Value(m.latitude),
            longitude: Value(m.longitude),
            placeId: Value(placeId),
            pairedVideoPath: Value(pair),
          ),
        );
    if (!item.probed) await _importOrganisation(item.id, m, facts.parsed.label);
    return ProbeResult(
      width: info.width,
      height: info.height,
      takenAt: m.captured,
      title: m.title,
      videoCodec: info.isMotionPhoto ? 'mp4' : null,
      hdrType: info.range == ImageDynamicRange.sdr ? null : 'gainmap',
    );
  }

  /// First look at a file: its star rating, keywords and colour label become
  /// the library's, unless the user already organised the photo here
  /// (IMG-005: tags are XMP `dc:subject`).
  Future<void> _importOrganisation(
    int itemId,
    ImageMetadata m,
    String? xmpLabel,
  ) async {
    final stars = m.rating;
    if (stars != null && stars > 0) {
      await db
          .into(db.ratings)
          .insert(
            RatingsCompanion.insert(
              itemId: Value(itemId),
              value: stars.clamp(1, 5) * 2,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    final color = labelFromXmp(xmpLabel);
    if (color != null) {
      await db
          .into(db.labels)
          .insert(
            LabelsCompanion.insert(itemId: Value(itemId), color: color),
            mode: InsertMode.insertOrIgnore,
          );
    }
    if (m.keywords.isNotEmpty && (await tags.tagsOf(itemId)).isEmpty) {
      for (final k in m.keywords.take(64)) {
        await tags.addTag([itemId], k);
      }
    }
  }

  /// `IMG_1234.MOV` next to `IMG_1234.HEIC`, as a path relative to the
  /// image's folder; null when there is none.
  Future<String?> _pairedVideo(Uri image) async {
    final segs = [...image.pathSegments];
    final name = segs.removeLast();
    final dot = name.lastIndexOf('.');
    final stem = dot < 0 ? name : name.substring(0, dot);
    for (final ext in _videoPairExtensions) {
      final candidate = image.replace(pathSegments: [...segs, '$stem.$ext']);
      try {
        if (await io.exists(candidate)) return '$stem.$ext';
      } on VirtualFileException {
        return null;
      }
    }
    return null;
  }

  /// Re-reads [item] after an edit (metadata written, file replaced) and
  /// refreshes the library row: new capture time, size, title.
  Future<void> reprobe(ItemRow item, VirtualFile file) async {
    final r = await probe(file, item);
    await IndexWriter(db).applyProbe(item.id, r);
  }
}

/// Maps the colour names photo programs write in `xmp:Label` (Lightroom:
/// Red, Yellow, Green, Blue, Purple; Bridge adds Orange) to a library label.
LabelColor? labelFromXmp(String? name) {
  if (name == null) return null;
  final n = name.trim().toLowerCase();
  for (final c in LabelColor.values) {
    if (c.name == n || c.name == n.replaceAll('gray', 'grey')) return c;
  }
  return null;
}
