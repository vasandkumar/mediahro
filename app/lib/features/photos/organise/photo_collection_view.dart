import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/batch/batch_screen.dart';
import 'package:mediahro/features/photos/compare/compare_screen.dart';
import 'package:mediahro/features/photos/edit/apply_look_flow.dart';
import 'package:mediahro/features/photos/edit/editor_screen.dart'
    show copiedLookProvider;
import 'package:mediahro/features/photos/map/location_actions.dart';
import 'package:mediahro/features/photos/organise/photo_actions.dart';
import 'package:mediahro/features/photos/organise/photo_selection.dart';
import 'package:mediahro/features/photos/organise/write_back.dart';
import 'package:mediahro/features/photos/output/output_actions.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_grid.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// A grid of photos with the selection bar that appears on top of it once
/// something is selected (IMG-005): favourite, add to album, rate, label,
/// tags, and, inside an album, remove from it.
class PhotoCollectionView extends ConsumerStatefulWidget {
  const PhotoCollectionView({
    required this.entries,
    required this.emptyMessage,
    this.albumId,
    this.emptyTitle,
    super.key,
  });

  final List<PhotoEntry> entries;
  final String emptyMessage;
  final String? emptyTitle;

  /// Set inside a manual album: adds "Remove from album".
  final int? albumId;

  @override
  ConsumerState<PhotoCollectionView> createState() =>
      _PhotoCollectionViewState();
}

class _PhotoCollectionViewState extends ConsumerState<PhotoCollectionView> {
  final PhotoSelection selection = PhotoSelection();

  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PhotoCollectionView old) {
    super.didUpdateWidget(old);
    // Forget selected photos that left the list (deleted, moved).
    final present = {for (final e in widget.entries) e.id};
    final gone = selection.ids.difference(present);
    if (gone.isNotEmpty) {
      selection.selectAll(selection.ids.intersection(present));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return KEmptyState(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
      );
    }
    return Stack(
      children: [
        PhotoGrid(
          entries: widget.entries,
          selection: selection,
          bottomPadding: 16,
        ),
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          child: ListenableBuilder(
            listenable: selection,
            builder: (context, _) => selection.active
                ? SelectionBar(
                    selection: selection,
                    entries: widget.entries,
                    albumId: widget.albumId,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// The contextual bar for the selected photos.
class SelectionBar extends ConsumerWidget {
  const SelectionBar({
    required this.selection,
    required this.entries,
    this.albumId,
    super.key,
  });

  final PhotoSelection selection;
  final List<PhotoEntry> entries;
  final int? albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final org = ref.read(photoOrganiserProvider);
    final ids = selection.ids;
    final chosen = [
      for (final e in entries)
        if (ids.contains(e.id)) e,
    ];
    final allFavourite = chosen.isNotEmpty && chosen.every((e) => e.favourite);
    final scheme = Theme.of(context).colorScheme;

    // Copies the change into the files when Settings asks for it; tells the
    // user only if some file could not be written.
    void writeBack(Future<int> Function(OrganisationWriteBack) run) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      unawaited(
        run(ref.read(organisationWriteBackProvider)).then((failed) {
          if (failed > 0) {
            messenger?.showSnackBar(
              SnackBar(content: Text(l10n.photosWriteBackFailed(failed))),
            );
          }
        }),
      );
    }

    Future<void> done(Future<void> Function() action) async {
      await action();
      if (context.mounted) selection.clear();
    }

    return Material(
      elevation: 3,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.photosClearSelection,
                icon: const Icon(Icons.close),
                onPressed: selection.clear,
              ),
              Expanded(
                child: Text(
                  l10n.photosSelectedCount(ids.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.photosSelectAll,
                icon: const Icon(Icons.select_all),
                onPressed: () =>
                    selection.selectAll([for (final e in entries) e.id]),
              ),
              IconButton(
                tooltip: allFavourite
                    ? l10n.photosUnfavourite
                    : l10n.photosFavourite,
                icon: Icon(
                  allFavourite ? Icons.favorite : Icons.favorite_border,
                ),
                onPressed: () => unawaited(
                  done(() => org.setFavourite(ids, value: !allFavourite)),
                ),
              ),
              IconButton(
                tooltip: l10n.photosAddToAlbum,
                icon: const Icon(Icons.photo_album_outlined),
                onPressed: () async {
                  final ok = await addToAlbumFlow(context, ref, ids);
                  if (ok && context.mounted) selection.clear();
                },
              ),
              PopupMenuButton<String>(
                tooltip: l10n.photosMore,
                onSelected: (v) async {
                  switch (v) {
                    case 'rate':
                      final stars = await askRating(context);
                      if (stars != null) {
                        await done(() => org.setRating(ids, stars));
                        writeBack((w) => w.rating(chosen, stars));
                      }
                    case 'label':
                      final c = await askLabel(context);
                      if (c == null) return;
                      final color = c is LabelColor ? c : null;
                      await done(() => org.setLabel(ids, color));
                      writeBack((w) => w.label(chosen, color));
                    case 'tags':
                      await editTagsFlow(context, ref, ids);
                      writeBack((w) => w.tags(chosen));
                    case 'share':
                      await showShareSheet(context, ref, chosen);
                    case 'print':
                      await printFlow(context, ref, chosen);
                    case 'batch':
                      final photos = chosen.where((e) => !e.isVideo).toList();
                      if (photos.isEmpty) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text(l10n.photosLocationNoPhotos)),
                        );
                      } else {
                        await openBatch(context, photos);
                      }
                    case 'applyLook':
                      if (await applyCopiedLookFlow(context, ref, chosen) &&
                          context.mounted) {
                        selection.clear();
                      }
                    case 'compare':
                      final photos = chosen.where((e) => !e.isVideo).toList();
                      if (photos.length < 2 || photos.length > 4) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text(l10n.photosCompareNeedTwo)),
                        );
                      } else {
                        await openCompare(context, photos);
                      }
                    case 'setLocation':
                      if (await setLocationFlow(context, ref, chosen) &&
                          context.mounted) {
                        selection.clear();
                      }
                    case 'clearLocation':
                      if (await clearLocationFlow(context, ref, chosen) &&
                          context.mounted) {
                        selection.clear();
                      }
                    case 'remove':
                      await done(() => org.removeFromAlbum(albumId!, ids));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rate', child: Text(l10n.photosRate)),
                  PopupMenuItem(
                    value: 'label',
                    child: Text(l10n.photosLabelAction),
                  ),
                  PopupMenuItem(
                    value: 'tags',
                    child: Text(l10n.photosTagsAction),
                  ),
                  if (ref.watch(copiedLookProvider) != null)
                    PopupMenuItem(
                      value: 'applyLook',
                      child: Text(l10n.photosApplyLook),
                    ),
                  PopupMenuItem(value: 'share', child: Text(l10n.photosShare)),
                  if (ref.watch(photoOutputSupportProvider).value?.print ??
                      false)
                    PopupMenuItem(
                      value: 'print',
                      child: Text(l10n.photosPrint),
                    ),
                  PopupMenuItem(value: 'batch', child: Text(l10n.photosBatch)),
                  PopupMenuItem(
                    value: 'compare',
                    child: Text(l10n.photosCompare),
                  ),
                  PopupMenuItem(
                    value: 'setLocation',
                    child: Text(l10n.photosSetLocationAction),
                  ),
                  PopupMenuItem(
                    value: 'clearLocation',
                    child: Text(l10n.photosClearLocationAction),
                  ),
                  if (albumId != null)
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(l10n.photosRemoveFromAlbum),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
