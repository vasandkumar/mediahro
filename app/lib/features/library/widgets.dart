import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Opens an indexed item for playback/viewing. The player lanes (C1–C3)
/// override this; by default nothing happens.
final openItemActionProvider =
    Provider<void Function(BuildContext context, ItemRow item)?>((ref) => null);

IconData kindIcon(ItemKind k) => switch (k) {
  ItemKind.video => Icons.movie_outlined,
  ItemKind.audio => Icons.music_note_outlined,
  ItemKind.image => Icons.image_outlined,
  ItemKind.playlist => Icons.queue_music_outlined,
  ItemKind.subtitle => Icons.subtitles_outlined,
  ItemKind.archive => Icons.folder_zip_outlined,
  ItemKind.other => Icons.insert_drive_file_outlined,
};

/// One indexed item in lists (search, folders, playlists, duplicates).
class ItemTile extends StatelessWidget {
  const ItemTile({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.trailing,
    this.resume,
    super.key,
  });

  final ItemRow item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final Widget? trailing;

  /// 0…1 resume bar (FILE-001 "thumbnails with resume bar").
  final double? resume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final facts = [
      if (item.durationMs != null)
        formatDuration(Duration(milliseconds: item.durationMs!)),
      ?resolutionLabel(item.height),
      if (item.hdrType != null && item.hdrType != 'none')
        item.hdrType!.toUpperCase(),
      formatBytes(
        item.size,
        locale: Localizations.localeOf(context).toLanguageTag(),
      ),
    ];
    return ListTile(
      minTileHeight: KTarget.min + KSpacing.s12,
      selected: selected,
      leading: Icon(
        kindIcon(item.kind),
        semanticLabel: l10n.libraryKindLabel(item.kind.name),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(facts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (resume != null)
            Padding(
              padding: const EdgeInsets.only(top: KSpacing.s4),
              child: LinearProgressIndicator(
                value: resume,
                semanticsLabel: l10n.libraryResumeProgress(
                  (resume! * 100).round(),
                ),
              ),
            ),
        ],
      ),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// docs/06 §9: one sentence and the actions, no illustration.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, this.actions = const [], super.key});

  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(KSpacing.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: KSpacing.s16),
          Wrap(
            spacing: KSpacing.s8,
            runSpacing: KSpacing.s8,
            alignment: WrapAlignment.center,
            children: actions,
          ),
        ],
      ),
    ),
  );
}

/// Skeleton rows while loading (docs/06 §9: skeletons, no spinners).
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.rows = 6, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.builder(
      itemCount: rows,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KSpacing.s16,
          vertical: KSpacing.s12,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(KRadius.sm),
              ),
            ),
            const SizedBox(width: KSpacing.s16),
            Expanded(child: Container(height: 14, color: c)),
          ],
        ),
      ),
    );
  }
}
