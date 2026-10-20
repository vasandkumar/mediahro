import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, ProviderException, ProviderFamily;
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/rules/rule_sql.dart' as rules;
import 'package:mediahro/features/photos/image_prober.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/map/map_providers.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/organise/write_back.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/photos_settings.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/settings/settings_providers.dart'
    show settingsStoreProvider;
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
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

final photoFilesProvider = Provider<PhotoFileOpener>((ref) {
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

/// Where thumbnails of a given edge (px) come from; tests replace it.
final ProviderFamily<ThumbnailSource, int> thumbnailSourceProvider =
    Provider.family<ThumbnailSource, int>(
      (ref, edge) => PipelineThumbnailSource(
        ref.watch(imagePipelineProvider),
        ref.watch(photoFilesProvider),
        edge: edge,
      ),
    );

/// Opens one image for the viewer; the returned [ViewerImage] closes the
/// file when disposed. Tests replace it.
typedef ViewerImageLoader = Future<ViewerImage> Function(PhotoEntry entry);

final viewerImageLoaderProvider = Provider<ViewerImageLoader>((ref) {
  final files = ref.watch(photoFilesProvider);
  final pipeline = ref.watch(imagePipelineProvider);
  return (entry) async {
    final src = await files.open(entry);
    try {
      return await loadViewerImage(pipeline, src, onDispose: src.file.close);
    } on Object {
      await src.file.close();
      rethrow;
    }
  };
});

/// What the details sheet shows about one photo.
typedef PhotoFacts = ({ImageInfo info, ParsedMetadata parsed});

final FutureProviderFamily<PhotoFacts, PhotoEntry> photoFactsProvider =
    FutureProvider.autoDispose.family<PhotoFacts, PhotoEntry>((
      ref,
      entry,
    ) async {
      final pipeline = ref.watch(imagePipelineProvider);
      final src = await ref.watch(photoFilesProvider).open(entry);
      try {
        final info = await pipeline.info(src);
        final parsed = await pipeline.parsedMetadata(src);
        return (info: info, parsed: parsed);
      } finally {
        await src.file.close();
      }
    });

/// Favourites, ratings, labels, tags and albums (IMG-005).
final photoOrganiserProvider = Provider<PhotoOrganiser>(
  (ref) => PhotoOrganiser(
    db: ref.watch(libraryDatabaseProvider),
    tags: ref.watch(tagRepositoryProvider),
    playlists: ref.watch(playlistRepositoryProvider),
  ),
);

/// Saves ratings, labels and tags into the files when the setting is on.
final organisationWriteBackProvider = Provider<OrganisationWriteBack>(
  (ref) => OrganisationWriteBack(
    editor: ref.watch(metadataEditServiceProvider),
    organiser: ref.watch(photoOrganiserProvider),
    enabled: () =>
        ref.read(settingsStoreProvider).get(PhotoSettings.writeOrganisation),
  ),
);

/// The photo albums with their sizes, refreshed when albums, their photos,
/// ratings or favourites change (smart albums follow their rules).
final photoAlbumsProvider = StreamProvider<List<PhotoAlbum>>((ref) async* {
  final db = ref.watch(libraryDatabaseProvider);
  final org = ref.watch(photoOrganiserProvider);
  final changes = db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.playlists,
          db.playlistItems,
          db.items,
          db.imageMeta,
          db.ratings,
          db.itemTags,
          db.labels,
        },
      )
      .watch();
  await for (final _ in changes) {
    yield await org.albums();
  }
});

/// Reads image facts for the library (plug into the probe queue for images).
final imageProberProvider = Provider<ImageProber>(
  (ref) => ImageProber(
    pipeline: ref.watch(imagePipelineProvider),
    db: ref.watch(libraryDatabaseProvider),
    io: MountedImageIo(ref.watch(mountsProvider)),
    places: ref.watch(placeResolverProvider),
  ),
);

final metadataEditServiceProvider = Provider<MetadataEditor>(
  (ref) => MetadataEditService(
    files: ref.watch(photoFilesProvider),
    pipeline: ref.watch(imagePipelineProvider),
    prober: ref.watch(imageProberProvider),
    db: ref.watch(libraryDatabaseProvider),
  ),
);

/// Photos and videos of the library, newest first, as light entries
/// (IMG-003). Re-queried (coalesced) when the index changes.
final photoEntriesProvider = StreamProvider<List<PhotoEntry>>((ref) async* {
  final db = ref.watch(libraryDatabaseProvider);
  final unlocked = ref.watch(visibilityProvider).value ?? false;
  final vis = rules.Visibility(unlocked: unlocked);
  final query = db.customSelect(
    photoEntriesSql(vis),
    readsFrom: {db.items, db.imageMeta, db.ratings, db.sources},
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
    'im.paired_video_path AS paired, rt.value AS rating '
    'FROM item i LEFT JOIN image_meta im ON im.item_id = i.id '
    'LEFT JOIN rating rt ON rt.item_id = i.id '
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
    rejected: (r.readNullable<int>('rating') ?? 0) < 0,
    livePhoto: r.readNullable<String>('paired') != null,
    // The prober records an embedded MP4 as the video codec of a still.
    motionPhoto: !isVideo && r.readNullable<String>('video_codec') == 'mp4',
    hdr: hdr != null && hdr != 'none',
  );
}
