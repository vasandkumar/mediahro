import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';

import '../../helpers.dart';

/// A valid 1×1 PNG, the "thumbnail" of every fake tile.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Entries over [days] days ending today, [perDay] a day, newest first.
List<PhotoEntry> fakeEntries({
  int days = 3,
  int perDay = 6,
  Set<int> raw = const {},
  Set<int> live = const {},
  Set<int> motion = const {},
  Set<int> hdr = const {},
  Set<int> videos = const {},
  Set<int> favourites = const {},
  int firstId = 0,
  String Function(int id)? folder,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 12);
  final out = <PhotoEntry>[];
  var id = firstId;
  for (var d = 0; d < days; d++) {
    for (var k = 0; k < perDay; k++) {
      final isVideo = videos.contains(id);
      final isRaw = raw.contains(id);
      final date = today.subtract(Duration(days: d, minutes: k));
      out.add(
        PhotoEntry(
          id: id,
          sourceId: 1,
          relPath:
              '${folder?.call(id) ?? 'p'}/IMG_$id.${isRaw
                  ? 'cr2'
                  : isVideo
                  ? 'mp4'
                  : 'jpg'}',
          name:
              'IMG_$id.${isRaw
                  ? 'cr2'
                  : isVideo
                  ? 'mp4'
                  : 'jpg'}',
          ext: isRaw
              ? 'cr2'
              : isVideo
              ? 'mp4'
              : 'jpg',
          isVideo: isVideo,
          size: 2 << 20,
          mtime: date,
          date: date,
          width: 4000,
          height: 3000,
          durationMs: isVideo ? 83000 : null,
          livePhoto: live.contains(id),
          motionPhoto: motion.contains(id),
          hdr: hdr.contains(id),
          favourite: favourites.contains(id),
        ),
      );
      id++;
    }
  }
  return out;
}

/// Records what the timeline asked for; resolves immediately with a PNG.
final class RecordingThumbnails implements ThumbnailSource {
  RecordingThumbnails(this.file);

  final File file;

  /// Keep loads pending until cancelled (a slow disk).
  bool hold = false;
  final Map<int, Completer<File>> _waiting = {};
  final List<(int, ThumbnailPriority)> loads = [];
  final List<int> cancelled = [];
  final List<(int, ThumbnailPriority)> bumps = [];

  @override
  Future<File> load(
    PhotoEntry entry,
    ThumbnailPriority priority,
    void Function(JobHandle) onQueued,
  ) async {
    loads.add((entry.id, priority));
    if (hold) return await (_waiting[entry.id] = Completer<File>()).future;
    return file;
  }

  @override
  void reprioritise(int entryId, ThumbnailPriority priority) =>
      bumps.add((entryId, priority));

  @override
  void cancel(int entryId) {
    cancelled.add(entryId);
    _waiting.remove(entryId)?.completeError(const JobCancelled());
  }
}

/// Everything a photos widget test needs.
final class PhotosHarness {
  PhotosHarness._(this.db, this.dir, this.thumbs, this._images);

  final LibraryDatabase db;
  final Directory dir;
  final RecordingThumbnails thumbs;
  final Queue<ViewerImage> _images;
  final List<PhotoEntry> opened = [];
  Exception? loadError;

  static Future<PhotosHarness> create(WidgetTester tester) async {
    final db = LibraryDatabase.memory();
    final dir = Directory.systemTemp.createTempSync('mediahro-photos-ui');
    final png = File('${dir.path}${Platform.pathSeparator}t.png')
      ..writeAsBytesSync(tinyPng);
    final images = Queue<ViewerImage>();
    // dart:ui image creation needs the real event loop.
    await tester.runAsync(() async {
      for (var i = 0; i < 12; i++) {
        final pixels = Uint8List(64 * 48 * 4)
          ..fillRange(0, 64 * 48 * 4, 120 + i);
        final img = await uiImageFrom(
          DecodedImage(width: 64, height: 48, pixels: pixels),
        );
        images.add(
          ViewerImage(
            base: img,
            fullSize: const ui.Size(4000, 3000),
            info: const ImageInfo(width: 4000, height: 3000, format: 'jpeg'),
          ),
        );
      }
    });
    final h = PhotosHarness._(db, dir, RecordingThumbnails(png), images);
    addTearDown(h.dispose);
    return h;
  }

  /// The next prepared viewer image.
  ViewerImage take() => _images.removeFirst();

  Future<void> dispose() async {
    await db.close();
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort on Windows.
      }
    }
  }

  PhotoFacts facts({ImageMetadata? metadata}) => (
    info: const ImageInfo(width: 4000, height: 3000, format: 'jpeg'),
    parsed: ParsedMetadata(
      blocks: const MetadataBlocks(format: ImageFormat.jpeg),
      metadata:
          metadata ??
          ImageMetadata(
            captured: DateTime(2026, 10, 21, 9, 30),
            cameraMake: 'Samsung',
            cameraModel: 'SM-M176B',
            lens: 'Main 5.4mm f/1.8',
            latitude: 12.975,
            longitude: 77.595833,
            title: 'Morning light',
            keywords: const ['lake', 'sunrise'],
            rating: 4,
            exif: const {'EXIF:Make': 'Samsung', 'EXIF:ISOSpeedRatings': '125'},
          ),
    ),
  );

  List<Override> overrides({
    required List<PhotoEntry> entries,
    PhotoFacts? facts,
    ViewerImageLoader? loader,
    List<Override> extra = const [],
  }) => [
    libraryDatabaseProvider.overrideWithValue(db),
    photoEntriesProvider.overrideWith((ref) => Stream.value(entries)),
    thumbnailSourceProvider.overrideWith((ref, edge) => thumbs),
    viewerImageLoaderProvider.overrideWithValue(
      loader ??
          (entry) async {
            opened.add(entry);
            final e = loadError;
            if (e != null) throw e;
            return _images.removeFirst();
          },
    ),
    photoFactsProvider.overrideWith(
      (ref, entry) async => facts ?? this.facts(),
    ),
    ...extra,
  ];

  /// The full app on the Photos tab with the viewer route registered.
  Future<void> pump(
    WidgetTester tester, {
    required List<PhotoEntry> entries,
    Size size = const Size(400, 800),
    PhotoFacts? facts,
    Map<String, Object?>? settings,
    List<Override> extra = const [],
  }) async {
    tester.view
      ..physicalSize = size * tester.view.devicePixelRatio
      ..devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final store =
        await tester.runAsync(() => memoryStore(settings)) ??
        (throw StateError('store'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          ...overrides(entries: entries, facts: facts, extra: extra),
        ],
        child: MediahroApp(
          router: buildRouter(
            initialLocation: '/photos',
            fullScreenRoutes: photoRoutes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
