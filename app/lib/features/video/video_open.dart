import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/item_locator.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/url_open.dart';
import 'package:mediahro/features/library/folder_browser_screen.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro/features/sources/open_url_dialog.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/video_player_screen.dart';
import 'package:mediahro/features/video/video_home_screen.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Containers the video player opens (VID-001); everything else goes to the
/// music or photo lanes.
const videoExtensions = {
  '3gp', 'asf', 'avi', 'flv', 'm2ts', 'm4v', 'mkv', 'mov', 'mp4', 'mpeg', //
  'mpg', 'mts', 'mxf', 'ogm', 'ogv', 'rm', 'rmvb', 'ts', 'vob', 'webm', 'wmv',
};

bool isVideoName(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 &&
      videoExtensions.contains(name.substring(dot + 1).toLowerCase());
}

abstract final class VideoRoutes {
  static const String play = '/play';
}

/// Full-screen player route (outside the shell). The orchestrator lists it
/// in `appRoutesProvider`.
final List<RouteBase> videoRoutes = [
  GoRoute(
    path: VideoRoutes.play,
    builder: (context, state) => switch (state.extra) {
      final PlayRequest r => VideoPlayerScreen(request: r),
      // A restored route has no request: go back to the video home.
      _ => const _Gone(),
    },
  ),
];

class _Gone extends StatefulWidget {
  const _Gone();

  @override
  State<_Gone> createState() => _GoneState();
}

class _GoneState extends State<_Gone> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/video');
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Opens [request] in the player.
void playVideo(BuildContext context, PlayRequest request) =>
    unawaited(context.push(VideoRoutes.play, extra: request));

const _directSchemes = {
  'fd',
  'fdclose',
  'file',
  'http',
  'https',
  'rtsp',
  'rtsps',
  'rtmp',
  'rtmps',
  'hls', //
  'udp', 'rtp', 'srt', 'mms', 'mmsh',
};

/// The engine source for [uri]: URIs mpv reads itself go direct, the rest
/// through the mounted source's [VirtualFile] (SMB, NFS, WebDAV, SAF…).
Future<MediaSource> mediaSourceFor(
  ProviderContainer container,
  Uri uri, {
  String? title,
  int? sourceId,
}) async {
  if (_directSchemes.contains(uri.scheme)) return UriSource(uri, title: title);
  final mounts = container.read(mountsProvider);
  VirtualFileSystem fs;
  try {
    fs = mounts.forUri(uri);
  } on VirtualFileException {
    if (sourceId == null) rethrow;
    // A library item on a source that is not browsed right now: mount it
    // for the session.
    final db = container.read(libraryDatabaseProvider);
    final row = await (db.select(
      db.sources,
    )..where((s) => s.id.equals(sourceId))).getSingle();
    final access = await container.read(sourceResolverProvider).resolve(row);
    fs = access.fileSystem();
    mounts.mount(access.root, fs);
  }
  return VirtualFileSource(await fs.open(uri), title: title);
}

/// Folder browser: a video file plays with the rest of its folder queued.
Future<bool> openVideoEntry(BuildContext context, VirtualEntry entry) async {
  if (entry.isDirectory || !isVideoName(entry.name)) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  final parent = entry.uri.resolve('.');
  var siblings = <VirtualEntry>[];
  try {
    siblings = await container
        .read(mountsProvider)
        .forUri(parent)
        .list(parent)
        .where((e) => !e.isDirectory && isVideoName(e.name))
        .toList()
        .timeout(const Duration(seconds: 3));
  } on Object {
    // Next-in-folder is a convenience; play the file regardless.
  }
  siblings.sort((a, b) => _natural(a.name, b.name));
  final after = siblings.indexWhere((e) => e.uri == entry.uri);
  PlayRequest req(VirtualEntry e, List<PlayRequest> next) => PlayRequest(
    resolve: () => mediaSourceFor(container, e.uri, title: e.name),
    title: e.name,
    memoryKey: e.uri.toString(),
    next: next,
    onDelete: () async {
      await container.read(fileOperationsProvider).delete([
        e.uri,
      ], allowPermanent: true);
    },
  );
  final next = [
    if (after >= 0)
      for (final e in siblings.skip(after + 1)) req(e, const []),
  ];
  if (!context.mounted) return true;
  playVideo(context, req(entry, next));
  return true;
}

/// Library: a video item plays with the following items of its folder or
/// series queued (VID-064).
Future<bool> openVideoItem(BuildContext context, ItemRow item) async {
  if (item.kind != ItemKind.video) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  final db = container.read(libraryDatabaseProvider);
  final locator = ItemLocator(db);
  final siblings =
      await (db.select(db.items)
            ..where(
              (i) =>
                  i.sourceId.equals(item.sourceId) &
                  i.parentPath.equals(item.parentPath) &
                  i.kind.equalsValue(ItemKind.video) &
                  i.missing.equals(false),
            )
            ..orderBy([(i) => OrderingTerm.asc(i.name)]))
          .get();
  siblings.sort((a, b) => _natural(a.name, b.name));
  final after = siblings.indexWhere((i) => i.id == item.id);
  PlayRequest req(ItemRow i, List<PlayRequest> next) => PlayRequest(
    resolve: () async => await mediaSourceFor(
      container,
      await locator.uriOf(i),
      title: i.title,
      sourceId: i.sourceId,
    ),
    title: i.title,
    memoryKey: 'item:${i.id}',
    itemId: i.id,
    seriesKey: i.parentPath.isEmpty
        ? null
        : 'folder:${i.sourceId}:${i.parentPath}',
    next: next,
    onDelete: () async {
      await container.read(fileOperationsProvider).delete([
        await locator.uriOf(i),
      ], allowPermanent: true);
    },
  );
  final next = [
    if (after >= 0)
      for (final i in siblings.skip(after + 1)) req(i, const []),
  ];
  if (!context.mounted) return true;
  playVideo(context, req(item, next));
  return true;
}

/// "Open a file" (CORE-002): the system picker, then the player. Android
/// hands out `content://` URIs, read through a detached descriptor.
Future<void> pickAndPlayVideo(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final StorageFacade storage;
  try {
    storage = container.read(storageProvider);
  } on Object {
    return;
  }
  final picked = await storage.pickFiles(kinds: const {PickKind.video});
  if (picked.isEmpty || !context.mounted) return;
  final f = picked.first;
  playVideo(
    context,
    PlayRequest(
      title: f.name,
      memoryKey: f.uri.toString(),
      resolve: () async {
        if (f.uri.scheme != 'content') {
          return await mediaSourceFor(container, f.uri, title: f.name);
        }
        // mpv reads the detached descriptor itself and closes it when the
        // item ends: no copy through Dart, full speed, seekable.
        final fd = await storage.openDocumentFd(f.uri);
        return UriSource(Uri.parse('fdclose://$fd'), title: f.name);
      },
    ),
  );
}

/// Open URL (CORE-005): plays the stream.
void openVideoUrl(BuildContext context, OpenableUrl url) => playVideo(
  context,
  PlayRequest.uri(url.uri, headers: url.headers, userAgent: url.userAgent),
);

/// "Episode 2" before "Episode 10".
int _natural(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).toList();
  final y = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i].group(0)!;
    final q = y[i].group(0)!;
    final pn = int.tryParse(p);
    final qn = int.tryParse(q);
    final c = pn != null && qn != null ? pn.compareTo(qn) : p.compareTo(q);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// Hooks for B2's library, folder browser and Open URL. The orchestrator
/// adds these to the app root (composed with the music and photo lanes'
/// handlers for their kinds).
final List<Override> videoOverrides = [
  videoLibraryProvider.overrideWith(
    (ref) => ref.watch(libraryDatabaseProvider),
  ),
  openItemActionProvider.overrideWithValue(
    (context, item) => unawaited(openVideoItem(context, item)),
  ),
  openFileActionProvider.overrideWithValue(
    (context, entry) => unawaited(openVideoEntry(context, entry)),
  ),
  openUrlActionProvider.overrideWithValue(openVideoUrl),
];
