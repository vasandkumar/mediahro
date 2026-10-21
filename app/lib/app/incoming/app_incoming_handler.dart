import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/incoming/incoming_intent.dart';
import 'package:mediahro/app/incoming/incoming_router.dart';
import 'package:mediahro/app/incoming/incoming_seams.dart';
import 'package:mediahro/app/incoming/incoming_target.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart' show AppDestination;
import 'package:mediahro/core/db/tables.dart' show ItemKind;
import 'package:mediahro/core/index/media_kind.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/viewer/external_image_viewer.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/video/last_played.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// What the app shows when it cannot open something another app handed over.
enum IncomingNotice { notOpened, unsupported, failed, playlistLater }

/// Makes the request that plays one item, with the items queued after it.
typedef _MakeRequest = PlayRequest Function(List<PlayRequest> next);

/// One file read through a grant, as the handler understands it.
typedef _Document = ({
  _MakeRequest? maker,
  ExternalImage? image,
  IncomingNotice? notice,
});

/// Opens what other apps hand to Mediahro (CORE-003 open-with, SYS-004 share
/// targets): video and audio in the player (audio in Music when Music offers
/// it), pictures in the external-image viewer, links as streams. Runs app
/// intents (SYS-003) by moving between the top-level screens. Everything is
/// untrusted input (see [classifyIncoming], [actionForIntent]).
///
/// Playlists and subtitle files from other apps are not opened yet.
final class AppIncomingHandler implements IncomingHandler {
  AppIncomingHandler(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  @override
  void runIntent(AppIntent intent) {
    switch (actionForIntent(intent)) {
      case IncomingGo(:final location):
        router.go(location);
      case IncomingPlaylist(:final name):
        unawaited(_playlist(name));
      case IncomingResume():
        unawaited(_resume());
      case IncomingIgnore():
        break;
    }
  }

  /// Starts the playlist in Music when Music offers it; otherwise opens Music
  /// and says it cannot yet.
  Future<void> _playlist(String name) async {
    var started = false;
    try {
      final play = container.read(playPlaylistByNameProvider);
      started = play != null && await play(name);
    } on Object {
      started = false;
    }
    router.go(AppDestination.music.path);
    if (!started) _show(IncomingNotice.playlistLater);
  }

  /// The last video played, or the mode last used.
  Future<void> _resume() async {
    try {
      final row = await lastPlayedVideo(
        container.read(libraryDatabaseProvider),
      );
      final context = _context();
      if (row != null && context != null && context.mounted) {
        await openVideoItem(context, row);
        return;
      }
    } on Object {
      // Falls through to the last mode.
    }
    final last = container
        .read(settingsStoreProvider)
        .get(CoreSettings.lastMode);
    router.go(AppDestination.isMode(last) ? '/$last' : '/video');
  }

  @override
  Future<void> openUris(List<Uri> uris) async {
    final roots = await _fileRoots();
    final makers = <_MakeRequest>[];
    final images = <ExternalImage>[];
    var imagesFirst = false;
    IncomingNotice? notice;
    for (final uri in uris.take(incomingLimit)) {
      switch (classifyIncoming(uri, fileRoots: roots)) {
        case IncomingRefused():
          notice ??= IncomingNotice.notOpened;
        case IncomingStream(:final url):
          // A link the user chose to open here: a user-opened stream, allowed
          // for this session like one typed into the open-link dialog.
          container.read(networkPolicyProvider).allowForSession(url.uri.host);
          await container.read(urlHistoryProvider).record(url);
          makers.add(
            (next) => PlayRequest.uri(
              url.uri,
              headers: url.headers,
              userAgent: url.userAgent,
              next: next,
            ),
          );
        case IncomingDocument(:final uri):
          try {
            final doc = await _document(uri);
            final maker = doc.maker;
            final image = doc.image;
            if (maker != null) makers.add(maker);
            if (image != null) {
              if (images.isEmpty && makers.isEmpty) imagesFirst = true;
              images.add(image);
            }
            notice ??= doc.notice;
          } on Object {
            notice ??= IncomingNotice.failed;
          }
      }
    }
    // What came first decides the screen: pictures open in the viewer, media in
    // the player; a mix opens what the first item is.
    if (images.isNotEmpty && (imagesFirst || makers.isEmpty)) {
      unawaited(
        router.push<void>(
          ExternalImageRoutes.view,
          extra: ExternalImageArgs(images),
        ),
      );
    } else if (makers.isNotEmpty) {
      // The first plays; the rest are queued after it.
      final queued = [for (final make in makers.skip(1)) make(const [])];
      unawaited(
        router.push<void>(VideoRoutes.play, extra: makers.first(queued)),
      );
    }
    if (notice != null) _show(notice);
  }

  Future<List<Uri>> _fileRoots() async {
    try {
      final grants = await container.read(storageProvider).grants();
      return [for (final g in grants) g.uri];
    } on Object {
      return const [];
    }
  }

  /// How to open one file: a way to play it, a picture to show, a notice saying
  /// why not, or nothing at all when Music took it.
  Future<_Document> _document(Uri uri) async {
    final storage = container.read(storageProvider);
    final entry = uri.scheme == 'content'
        ? await storage.statDocument(uri)
        : null;
    final name =
        entry?.name ?? (uri.pathSegments.isEmpty ? '' : uri.pathSegments.last);
    var kind = MediaKinds.classify(name);
    final mime = entry?.mimeType ?? '';
    if (kind == ItemKind.other) {
      if (mime.startsWith('video/')) kind = ItemKind.video;
      if (mime.startsWith('audio/')) kind = ItemKind.audio;
      if (mime.startsWith('image/')) kind = ItemKind.image;
    }
    switch (kind) {
      case ItemKind.image:
        return (maker: null, image: ExternalImage(uri, name), notice: null);
      case ItemKind.audio:
        // Music plays it when it offers to; otherwise the player does.
        final music = container.read(playExternalAudioProvider);
        if (music != null && await music(uri)) {
          return (maker: null, image: null, notice: null);
        }
        return _playable(uri, name, storage);
      case ItemKind.video:
        return _playable(uri, name, storage);
      case ItemKind.playlist ||
          ItemKind.subtitle ||
          ItemKind.archive ||
          ItemKind.other:
        return (maker: null, image: null, notice: IncomingNotice.unsupported);
    }
  }

  _Document _playable(Uri uri, String name, StorageFacade storage) => (
    maker: (List<PlayRequest> next) => PlayRequest(
      title: name,
      memoryKey: uri.toString(),
      next: next,
      resolve: () async {
        if (uri.scheme != 'content') {
          return await mediaSourceFor(container, uri, title: name);
        }
        // mpv reads the detached descriptor itself and closes it when the item
        // ends: no copy through Dart, seekable.
        final fd = await storage.openDocumentFd(uri);
        return UriSource(Uri.parse('fdclose://$fd'), title: name);
      },
    ),
    image: null,
    notice: null,
  );

  BuildContext? _context() => router.routerDelegate.navigatorKey.currentContext;

  void _show(IncomingNotice notice) {
    final context = _context();
    if (context == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final text = switch (notice) {
      IncomingNotice.notOpened => l10n.appIncomingNotOpened,
      IncomingNotice.unsupported => l10n.appIncomingUnsupported,
      IncomingNotice.failed => l10n.appIncomingFailed,
      IncomingNotice.playlistLater => l10n.appIncomingPlaylistLater,
    };
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }
}
