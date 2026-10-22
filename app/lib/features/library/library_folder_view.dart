import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/source_repository.dart'
    show SourceSummary;
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// What one folder holds for a mode: its sub-folders and the items directly in it.
typedef FolderListing = (List<FolderEntry>, List<ItemRow>);

final FutureProviderFamily<FolderListing, (LibraryMode, int, String)>
_folderListingProvider = FutureProvider.autoDispose
    .family<FolderListing, (LibraryMode, int, String)>((ref, key) async {
      final (mode, sourceId, path) = key;
      final views = ref.watch(libraryViewsProvider);
      return (
        await views.folders(sourceId, path, mode),
        await views.folderItems(sourceId, path, mode),
      );
    });

/// The folder view of a mode (LIB-004): its sources, then their folders and
/// the items of [mode] in each, from the library index. Items open through
/// [onOpen]. A single source opens straight at its root.
class LibraryFolderView extends ConsumerWidget {
  const LibraryFolderView({
    required this.mode,
    required this.onOpen,
    super.key,
  });

  final LibraryMode mode;
  final void Function(BuildContext context, ItemRow item) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(sourceSummariesProvider).value;
    if (sources == null) return const SizedBox.shrink();
    if (sources.isEmpty) return KEmptyState(message: l10n.libraryFolderEmpty);
    if (sources.length == 1) {
      return LibraryFolderContents(
        mode: mode,
        sourceId: sources.single.source.id,
        path: '',
        onOpen: onOpen,
      );
    }
    return ListView(
      children: [
        for (final s in sources)
          KRow(
            title: s.source.name,
            subtitle: l10n.libraryFolderItemCount(s.items),
            leading: Icon(KIcon.folder.resolve(Theme.of(context).family)),
            onTap: () => _open(context, s),
          ),
      ],
    );
  }

  void _open(BuildContext context, SourceSummary s) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LibraryFolderScreen(
          mode: mode,
          sourceId: s.source.id,
          path: '',
          title: s.source.name,
          onOpen: onOpen,
        ),
      ),
    );
  }
}

/// One folder as its own screen, pushed from the list.
class LibraryFolderScreen extends StatelessWidget {
  const LibraryFolderScreen({
    required this.mode,
    required this.sourceId,
    required this.path,
    required this.title,
    required this.onOpen,
    super.key,
  });

  final LibraryMode mode;
  final int sourceId;
  final String path;
  final String title;
  final void Function(BuildContext context, ItemRow item) onOpen;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: LibraryFolderContents(
      mode: mode,
      sourceId: sourceId,
      path: path,
      onOpen: onOpen,
    ),
  );
}

/// The sub-folders and items of one folder.
class LibraryFolderContents extends ConsumerWidget {
  const LibraryFolderContents({
    required this.mode,
    required this.sourceId,
    required this.path,
    required this.onOpen,
    super.key,
  });

  final LibraryMode mode;
  final int sourceId;
  final String path;
  final void Function(BuildContext context, ItemRow item) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final listing = ref.watch(_folderListingProvider((mode, sourceId, path)));
    final data = listing.value;
    if (data == null) return const SizedBox.shrink();
    final (folders, items) = data;
    if (folders.isEmpty && items.isEmpty) {
      return KEmptyState(message: l10n.libraryFolderEmpty);
    }
    final family = Theme.of(context).family;
    return ListView(
      children: [
        for (final f in folders)
          KRow(
            title: f.name,
            subtitle: l10n.libraryFolderItemCount(f.itemCount),
            leading: Icon(KIcon.folder.resolve(family)),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => LibraryFolderScreen(
                  mode: mode,
                  sourceId: sourceId,
                  path: f.path,
                  title: f.name,
                  onOpen: onOpen,
                ),
              ),
            ),
          ),
        for (final item in items)
          ItemTile(item: item, onTap: () => onOpen(context, item)),
      ],
    );
  }
}
