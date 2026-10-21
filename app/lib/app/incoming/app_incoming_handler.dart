import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/incoming/incoming_intent.dart';
import 'package:mediahro/app/incoming/incoming_router.dart';
import 'package:mediahro/app/incoming/incoming_target.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart' show AppDestination;
import 'package:mediahro/core/db/tables.dart' show ItemKind;
import 'package:mediahro/core/index/media_kind.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// What the app shows when it cannot open something another app handed over.
enum IncomingNotice { notOpened, unsupported, imageViewer, failed }

/// Makes the request that plays one item, with the items queued after it.
typedef _MakeRequest = PlayRequest Function(List<PlayRequest> next);

/// Opens what other apps hand to Mediahro (CORE-003 open-with, SYS-004 share
/// targets) in the player, and runs app intents (SYS-003) by moving between the
/// top-level screens. Everything is untrusted input (see [classifyIncoming],
/// [actionForIntent]).
///
/// Video and audio play in the player. Images, playlists and subtitle files
/// from other apps are not opened yet: the photo viewer shows library photos
/// only, and the others need an entry point in their lane.
final class AppIncomingHandler implements IncomingHandler {
  AppIncomingHandler(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  @override
  void runIntent(AppIntent intent) {
    switch (actionForIntent(intent)) {
      case IncomingGo(:final location):
        router.go(location);
      case IncomingResume():
        final last = container
            .read(settingsStoreProvider)
            .get(CoreSettings.lastMode);
        router.go(AppDestination.isMode(last) ? '/$last' : '/video');
      case IncomingIgnore():
        break;
    }
  }

  @override
  Future<void> openUris(List<Uri> uris) async {
    final roots = await _fileRoots();
    final makers = <_MakeRequest>[];
    IncomingNotice? notice;
    for (final uri in uris.take(incomingLimit)) {
      final target = classifyIncoming(uri, fileRoots: roots);
      switch (target) {
        case IncomingRefused(:final reason):
          notice ??= switch (reason) {
            IncomingRefusal.scheme ||
            IncomingRefusal.notPermitted => IncomingNotice.notOpened,
            IncomingRefusal.unsupportedType => IncomingNotice.unsupported,
            IncomingRefusal.imageViewer => IncomingNotice.imageViewer,
          };
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
            final (:maker, notice: why) = await _document(uri);
            if (maker != null) makers.add(maker);
            notice ??= why;
          } on Object {
            notice ??= IncomingNotice.failed;
          }
      }
    }
    if (makers.isNotEmpty) {
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

  /// How to play a video or audio file, or the [IncomingNotice] saying why it
  /// is not opened.
  Future<({_MakeRequest? maker, IncomingNotice? notice})> _document(
    Uri uri,
  ) async {
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
        return (maker: null, notice: IncomingNotice.imageViewer);
      case ItemKind.video || ItemKind.audio:
        return (
          maker: (List<PlayRequest> next) => PlayRequest(
            title: name,
            memoryKey: uri.toString(),
            next: next,
            resolve: () async {
              if (uri.scheme != 'content') {
                return await mediaSourceFor(container, uri, title: name);
              }
              // mpv reads the detached descriptor itself and closes it when
              // the item ends: no copy through Dart, seekable.
              final fd = await storage.openDocumentFd(uri);
              return UriSource(Uri.parse('fdclose://$fd'), title: name);
            },
          ),
          notice: null,
        );
      case ItemKind.playlist ||
          ItemKind.subtitle ||
          ItemKind.archive ||
          ItemKind.other:
        return (maker: null, notice: IncomingNotice.unsupported);
    }
  }

  void _show(IncomingNotice notice) {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final text = switch (notice) {
      IncomingNotice.notOpened => l10n.appIncomingNotOpened,
      IncomingNotice.unsupported => l10n.appIncomingUnsupported,
      IncomingNotice.imageViewer => l10n.appIncomingImage,
      IncomingNotice.failed => l10n.appIncomingFailed,
    };
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }
}
