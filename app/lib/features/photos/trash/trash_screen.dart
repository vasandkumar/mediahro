import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/trash/app_trash.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Asks, then moves [photos] to Recently deleted (IMG-014); photos too big for
/// the bin go to the system trash. Returns true when something was deleted.
Future<bool> deletePhotosFlow(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> photos,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The widget that started this may be gone before the undo is tapped.
  final container = ProviderScope.containerOf(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.photosTrashConfirmTitle(photos.length)),
      content: Text(l10n.photosTrashConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.photosTrashConfirm),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final trash = container.read(appTrashProvider);
  final outcome = await trash.moveToTrash(photos);
  var system = 0;
  if (outcome.tooBig.isNotEmpty) {
    try {
      final files = container.read(photoFilesProvider);
      final result = await container.read(fileOperationsProvider).delete([
        for (final p in outcome.tooBig) await files.uriOf(p),
      ]);
      system = result.trashed.length + result.deleted.length;
    } on Object {
      system = 0;
    }
  }
  container.invalidate(trashContentsProvider);
  final failed = outcome.failed.length + outcome.tooBig.length - system;
  final done = outcome.moved.length + system;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        [
          if (done > 0) l10n.photosTrashed(done),
          if (system > 0) l10n.photosTrashLarge(system),
          if (failed > 0) l10n.photosTrashFailed(failed),
        ].join(' '),
      ),
      action: outcome.moved.isEmpty
          ? null
          : SnackBarAction(
              label: l10n.photosTrashUndo,
              onPressed: () {
                unawaited(
                  trash.restore(outcome.moved).then((_) {
                    container.invalidate(trashContentsProvider);
                  }),
                );
              },
            ),
    ),
  );
  return done > 0;
}

/// Recently deleted: what can still be brought back.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  final Set<String> _chosen = {};

  Future<void> _restore(List<TrashedPhoto> items) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final n = await ref.read(appTrashProvider).restore(items);
    ref.invalidate(trashContentsProvider);
    setState(_chosen.clear);
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.photosTrashRestored(n))),
    );
  }

  Future<void> _forever(List<TrashedPhoto> items, {String? body}) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          body ?? l10n.photosTrashDeleteForeverConfirm(items.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photosTrashDeleteForever),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(appTrashProvider).deleteForever(items);
    ref.invalidate(trashContentsProvider);
    setState(_chosen.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trash = ref.watch(appTrashProvider);
    final items = ref.watch(trashContentsProvider).value;
    final chosen = [
      for (final t in items ?? const <TrashedPhoto>[])
        if (_chosen.contains(t.id)) t,
    ];
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _chosen.isEmpty
              ? l10n.photosTrashTitle
              : l10n.photosSelectedCount(_chosen.length),
        ),
        actions: [
          if (_chosen.isNotEmpty) ...[
            IconButton(
              tooltip: l10n.photosTrashRestore,
              icon: const Icon(Icons.restore_from_trash),
              onPressed: () => unawaited(_restore(chosen)),
            ),
            IconButton(
              tooltip: l10n.photosTrashDeleteForever,
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () => unawaited(_forever(chosen)),
            ),
          ] else if (items != null && items.isNotEmpty)
            TextButton(
              onPressed: () => unawaited(
                _forever(items, body: l10n.photosTrashEmptyAllConfirm),
              ),
              child: Text(l10n.photosTrashEmptyAll),
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? KEmptyState(
              title: l10n.photosTrashEmptyTitle,
              message: l10n.photosTrashEmptyMessage,
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final t = items[i];
                final selected = _chosen.contains(t.id);
                final left =
                    (trash.keepFor.inDays - now.difference(t.deletedAt).inDays)
                        .clamp(0, trash.keepFor.inDays);
                return Semantics(
                  button: true,
                  selected: selected,
                  label: '${t.name}, ${l10n.photosTrashDaysLeft(left)}',
                  excludeSemantics: true,
                  onTap: () => setState(
                    () => selected ? _chosen.remove(t.id) : _chosen.add(t.id),
                  ),
                  child: InkWell(
                    onTap: () => setState(
                      () => selected ? _chosen.remove(t.id) : _chosen.add(t.id),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (t.isVideo)
                          const ColoredBox(
                            color: Colors.black26,
                            child: Icon(Icons.movie_outlined),
                          )
                        else
                          Image.file(
                            trash.fileOf(t),
                            fit: BoxFit.cover,
                            cacheWidth: 280,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Colors.black26,
                              child: Icon(Icons.image_not_supported_outlined),
                            ),
                          ),
                        if (selected)
                          ColoredBox(
                            color: Theme.of(context).colorScheme.primary
                                .withValues(alpha: 0.35),
                            child: const Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            child: Text(
                              l10n.photosTrashDaysLeft(left),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
