import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';

/// A timeline entry for an indexed item (the light view of one row).
PhotoEntry photoEntryFromItem(ItemRow r) => PhotoEntry(
  id: r.id,
  sourceId: r.sourceId,
  relPath: r.relPath,
  name: r.name,
  ext: r.ext.toLowerCase(),
  isVideo: r.kind == ItemKind.video,
  size: r.size,
  mtime: r.mtime,
  date: r.takenAt ?? r.mtime,
  width: r.width,
  height: r.height,
  durationMs: r.durationMs,
  motionPhoto: r.kind == ItemKind.image && r.videoCodec == 'mp4',
  hdr: r.hdrType != null && r.hdrType != 'none',
);

/// The viewer arguments for opening [item] from outside the timeline
/// (search results, folder browser): the viewer pages through the photos of
/// the item's folder, starting on it.
Future<PhotoViewerArgs> viewerArgsFor(LibraryViews views, ItemRow item) async {
  final rows = await views.folderItems(
    item.sourceId,
    item.parentPath,
    LibraryMode.photos,
  );
  final entries = [for (final r in rows) photoEntryFromItem(r)];
  final at = entries.indexWhere((e) => e.id == item.id);
  if (at >= 0) return PhotoViewerArgs(entries, at);
  return PhotoViewerArgs([photoEntryFromItem(item)], 0);
}

/// Opens an image item in the viewer. The orchestrator's
/// `openItemActionProvider` dispatcher calls this for `ItemKind.image`.
void openImageItem(BuildContext context, ItemRow item) {
  final container = ProviderScope.containerOf(context);
  unawaited(
    viewerArgsFor(container.read(libraryViewsProvider), item).then((args) {
      if (context.mounted) {
        unawaited(openPhotoViewer(context, args.entries, args.index));
      }
    }),
  );
}
