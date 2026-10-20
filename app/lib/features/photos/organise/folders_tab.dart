import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/source_repository.dart'
    show SourceSummary;
import 'package:mediahro/features/photos/organise/folder_tree.dart';
import 'package:mediahro/features/photos/organise/photo_collection_view.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_layout.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The folder trees of all sources, rebuilt when the entries change.
final Provider<Map<int, FolderNode>> photoFolderTreesProvider =
    Provider<Map<int, FolderNode>>(
      (ref) => buildFolderTrees(
        ref.watch(photoEntriesProvider).value ?? const <PhotoEntry>[],
      ),
    );

/// The Folders tab: each source with photos, opening into its folders
/// (IMG-005). With a single source its root opens directly.
class FoldersTab extends ConsumerWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trees = ref.watch(photoFolderTreesProvider);
    if (trees.isEmpty) {
      return KEmptyState(message: l10n.photosFoldersEmpty);
    }
    if (trees.length == 1) {
      return FolderContents(sourceId: trees.keys.single, path: '');
    }
    final names = {
      for (final s
          in ref.watch(sourceSummariesProvider).value ??
              const <SourceSummary>[])
        s.source.id: s.source.name,
    };
    return ListView(
      children: [
        for (final t in trees.values)
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(
              names[t.sourceId] ?? l10n.photosSourceUnnamed(t.sourceId),
            ),
            subtitle: Text(l10n.photosFolderCount(t.total)),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => FolderScreen(
                  sourceId: t.sourceId,
                  path: '',
                  title:
                      names[t.sourceId] ?? l10n.photosSourceUnnamed(t.sourceId),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A folder as its own screen (pushed from the list).
class FolderScreen extends StatelessWidget {
  const FolderScreen({
    required this.sourceId,
    required this.path,
    required this.title,
    super.key,
  });

  final int sourceId;
  final String path;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: const [PhotoLayoutActions()]),
    body: FolderContents(sourceId: sourceId, path: path),
  );
}

/// Sub-folders on top, the photos directly in the folder below.
class FolderContents extends ConsumerWidget {
  const FolderContents({required this.sourceId, required this.path, super.key});

  final int sourceId;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final node = ref.watch(photoFolderTreesProvider)[sourceId]?.find(path);
    if (node == null) return KEmptyState(message: l10n.photosFoldersEmpty);
    final folders = node.sortedChildren;
    final height = MediaQuery.sizeOf(context).height;
    return Column(
      children: [
        if (folders.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.35),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in folders)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(f.name),
                    subtitle: Text(l10n.photosFolderCount(f.total)),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => FolderScreen(
                          sourceId: sourceId,
                          path: f.path,
                          title: f.name,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: PhotoCollectionView(
            entries: node.photos,
            emptyMessage: l10n.photosFoldersEmpty,
          ),
        ),
      ],
    );
  }
}
