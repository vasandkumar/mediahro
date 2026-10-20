import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/rules/rule_sql.dart' as rules;
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Whether the app runs with a library database (always in the app; shell
/// tests run without one).
final photosLibraryAvailableProvider = Provider<bool>((ref) {
  try {
    ref.watch(libraryDatabaseProvider);
    return true;
  } on Object {
    return false;
  }
});

/// The image worker isolates: half the cores, at most four.
final imageWorkerProvider = Provider<ImageWorkerClient>((ref) {
  final c = ImageWorkerClient.create(
    size: (Platform.numberOfProcessors ~/ 2).clamp(1, 4),
  );
  ref.onDispose(() => unawaited(c.dispose()));
  return c;
});

/// 512 MiB of thumbnails under the app data folder (IMG-003); Settings can
/// clear it.
final thumbnailCacheProvider = Provider<ThumbnailCache>((ref) {
  final root = ref.watch(appDataDirectoryProvider).path;
  final c = ThumbnailCache(
    db: ref.watch(libraryDatabaseProvider),
    directory: Directory('$root${Platform.pathSeparator}thumbs'),
  );
  ref.onDispose(() => unawaited(c.dispose()));
  return c;
});

final photoFilesProvider = Provider<PhotoFiles>((ref) {
  final f = PhotoFiles(
    ref.watch(libraryDatabaseProvider),
    ref.watch(sourceResolverProvider),
    ref.watch(mountsProvider),
  );
  ref.onDispose(() => unawaited(f.close()));
  return f;
});

final imagePipelineProvider = Provider<MediahroImagePipeline>((ref) {
  ImagingFacade? imaging;
  try {
    imaging = ref.watch(imagingProvider);
  } on PlatformCapabilityUnavailable {
    imaging = null;
  } on ProviderException catch (e) {
    // Riverpod 3 wraps what a provider threw when another one reads it.
    if (e.exception is! PlatformCapabilityUnavailable) rethrow;
  }
  final p = MediahroImagePipeline(
    worker: ref.watch(imageWorkerProvider),
    cache: ref.watch(thumbnailCacheProvider),
    io: MountedImageIo(ref.watch(mountsProvider)),
    imaging: imaging,
  );
  return p;
});

/// Photos and videos of the library, newest first, as light entries
/// (IMG-003). Re-queried (coalesced) when the index changes.
final photoEntriesProvider = StreamProvider<List<PhotoEntry>>((ref) async* {
  final db = ref.watch(libraryDatabaseProvider);
  final unlocked = ref.watch(visibilityProvider).value ?? false;
  final vis = rules.Visibility(unlocked: unlocked);
  final query = db.customSelect(
    photoEntriesSql(vis),
    readsFrom: {db.items, db.imageMeta, db.sources},
  );
  var first = true;
  await for (final _ in query.watch().map((_) {})) {
    // The scanner writes thousands of rows in bursts: wait for it to settle.
    if (!first) await Future<void>.delayed(const Duration(milliseconds: 600));
    first = false;
    yield await loadPhotoEntries(query);
  }
});

String photoEntriesSql(rules.Visibility vis) =>
    'SELECT i.id, i.source_id, i.rel_path, i.name, i.ext, i.kind, i.size, '
    'i.mtime, i.taken_at, i.width, i.height, i.duration_ms, i.video_codec, '
    'i.hdr_type, im.orientation AS ori, im.favourite AS fav, '
    'im.paired_video_path AS paired '
    'FROM item i LEFT JOIN image_meta im ON im.item_id = i.id '
    "WHERE ${vis.sql} AND i.kind IN ('image', 'video') "
    'ORDER BY coalesce(i.taken_at, i.mtime) DESC, i.id DESC';

/// Runs the entries query and maps the rows, yielding to the UI every few
/// thousand rows so a 100 k library does not freeze a frame.
Future<List<PhotoEntry>> loadPhotoEntries(Selectable<QueryRow> query) async {
  final rows = await query.get();
  final out = <PhotoEntry>[];
  for (var i = 0; i < rows.length; i++) {
    out.add(photoEntryFromRow(rows[i]));
    if (i % 4000 == 3999) await Future<void>.delayed(Duration.zero);
  }
  return out;
}

DateTime _seconds(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);

PhotoEntry photoEntryFromRow(QueryRow r) {
  final mtime = _seconds(r.read<int>('mtime'));
  final taken = r.readNullable<int>('taken_at');
  final isVideo = r.read<String>('kind') == ItemKind.video.name;
  final hdr = r.readNullable<String>('hdr_type');
  return PhotoEntry(
    id: r.read<int>('id'),
    sourceId: r.read<int>('source_id'),
    relPath: r.read<String>('rel_path'),
    name: r.read<String>('name'),
    ext: r.read<String>('ext').toLowerCase(),
    isVideo: isVideo,
    size: r.read<int>('size'),
    mtime: mtime,
    date: taken == null ? mtime : _seconds(taken),
    width: r.readNullable<int>('width'),
    height: r.readNullable<int>('height'),
    durationMs: r.readNullable<int>('duration_ms'),
    orientation: r.readNullable<int>('ori'),
    favourite: r.readNullable<bool>('fav') ?? false,
    livePhoto: r.readNullable<String>('paired') != null,
    // The prober records an embedded MP4 as the video codec of a still.
    motionPhoto: !isVideo && r.readNullable<String>('video_codec') == 'mp4',
    hdr: hdr != null && hdr != 'none',
  );
}
