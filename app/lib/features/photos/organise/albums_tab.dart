import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:mediahro/features/library/playlists_screen.dart'
    show SmartRuleEditor;
import 'package:mediahro/features/photos/organise/photo_actions.dart';
import 'package:mediahro/features/photos/organise/photo_collection_view.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_layout.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The photos of one album, newest first. Refreshes when the album, the
/// library or the ratings and favourites a smart album tests change.
final StreamProviderFamily<List<PhotoEntry>, int> photoAlbumEntriesProvider =
    StreamProvider.family<List<PhotoEntry>, int>((ref, albumId) async* {
      final db = ref.watch(libraryDatabaseProvider);
      final org = ref.watch(photoOrganiserProvider);
      final entries =
          ref.watch(photoEntriesProvider).value ?? const <PhotoEntry>[];
      final changes = db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              db.playlists,
              db.playlistItems,
              db.imageMeta,
              db.ratings,
              db.itemTags,
              db.labels,
            },
          )
          .watch();
      await for (final _ in changes) {
        final ids = (await org.albumItemIds(albumId)).toSet();
        yield [
          for (final e in entries)
            if (ids.contains(e.id)) e,
        ];
      }
    });

/// The two albums every library has, computed from the photos themselves.
enum SystemAlbum { favourites, rejected }

/// The Albums tab: Favourites, then the user's and smart albums (IMG-005).
class AlbumsTab extends ConsumerStatefulWidget {
  const AlbumsTab({super.key});

  @override
  ConsumerState<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends ConsumerState<AlbumsTab> {
  late final ThumbnailController _thumbs;

  @override
  void initState() {
    super.initState();
    _thumbs = ThumbnailController(ref.read(thumbnailSourceProvider(256)));
  }

  @override
  void dispose() {
    _thumbs.dispose();
    super.dispose();
  }

  Future<void> _newAlbum() async {
    final name = await askAlbumName(context);
    if (name == null) return;
    await ref.read(photoOrganiserProvider).createAlbum(name);
  }

  Future<void> _newSmart() async {
    final result = await Navigator.of(context).push<(String, SmartRule)>(
      MaterialPageRoute(builder: (_) => const SmartRuleEditor()),
    );
    if (result == null) return;
    await ref
        .read(photoOrganiserProvider)
        .createSmartAlbum(result.$1, result.$2);
  }

  void _open(PhotoAlbum? album, [SystemAlbum system = SystemAlbum.favourites]) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AlbumScreen(album: album, system: system),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final albums = ref.watch(photoAlbumsProvider).value ?? const <PhotoAlbum>[];
    final all = ref.watch(photoEntriesProvider).value ?? const <PhotoEntry>[];
    final byId = {for (final e in all) e.id: e};
    final favourites = all.where((e) => e.favourite).length;
    final rejected = all.where((e) => e.rejected).length;
    return Scaffold(
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(l10n.photosFavourites),
            subtitle: Text(l10n.photosAlbumCount(favourites)),
            onTap: () => _open(null),
          ),
          if (rejected > 0)
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: Text(l10n.photosRejected),
              subtitle: Text(l10n.photosAlbumCount(rejected)),
              onTap: () => _open(null, SystemAlbum.rejected),
            ),
          for (final a in albums)
            ListTile(
              leading: SizedBox.square(
                dimension: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(KRadius.sm),
                  child: byId[a.coverItemId] == null
                      ? ColoredBox(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Icon(
                            a.smart
                                ? Icons.auto_awesome_outlined
                                : Icons.photo_album_outlined,
                          ),
                        )
                      : PhotoThumbnail(
                          entry: byId[a.coverItemId]!,
                          index: 0,
                          controller: _thumbs,
                        ),
                ),
              ),
              title: Text(a.name),
              subtitle: Text(
                a.smart
                    ? '${l10n.photosSmartAlbum} · ${l10n.photosAlbumCount(a.count)}'
                    : l10n.photosAlbumCount(a.count),
              ),
              onTap: () => _open(a),
            ),
          if (albums.isEmpty)
            Padding(
              padding: const EdgeInsets.all(KSpacing.s24),
              child: Text(
                l10n.photosAlbumsEmpty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 88),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(l10n.photosNewAlbum),
      ),
    );
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_album_outlined),
              title: Text(l10n.photosNewAlbum),
              onTap: () => Navigator.of(ctx).pop('album'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.photosNewSmartAlbum),
              onTap: () => Navigator.of(ctx).pop('smart'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'album') await _newAlbum();
    if (choice == 'smart') await _newSmart();
  }
}

/// One album's photos; [album] null is the [system] album.
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({
    required this.album,
    this.system = SystemAlbum.favourites,
    super.key,
  });

  final PhotoAlbum? album;
  final SystemAlbum system;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final a = album;
    final List<PhotoEntry> entries;
    if (a == null) {
      entries = [
        for (final e
            in ref.watch(photoEntriesProvider).value ?? const <PhotoEntry>[])
          if (system == SystemAlbum.rejected ? e.rejected : e.favourite) e,
      ];
    } else {
      entries =
          ref.watch(photoAlbumEntriesProvider(a.id)).value ??
          const <PhotoEntry>[];
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          a?.name ??
              (system == SystemAlbum.rejected
                  ? l10n.photosRejected
                  : l10n.photosFavourites),
        ),
        actions: [
          const PhotoLayoutActions(),
          if (a != null)
            PopupMenuButton<String>(
              tooltip: l10n.photosMore,
              onSelected: (v) async {
                final org = ref.read(photoOrganiserProvider);
                final nav = Navigator.of(context);
                if (v == 'rename') {
                  final name = await askAlbumName(
                    context,
                    initial: a.name,
                    rename: true,
                  );
                  if (name != null) await org.renameAlbum(a.id, name);
                } else {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.photosDeleteAlbum),
                      content: Text(l10n.photosDeleteAlbumMessage(a.name)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(l10n.photosCancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(l10n.photosDelete),
                        ),
                      ],
                    ),
                  );
                  if (ok ?? false) {
                    await org.deleteAlbum(a.id);
                    nav.pop();
                  }
                }
              },
              itemBuilder: (_) => [
                if (!a.smart)
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(l10n.photosRename),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(l10n.photosDeleteAlbum),
                ),
              ],
            ),
        ],
      ),
      body: PhotoCollectionView(
        entries: entries,
        albumId: a != null && !a.smart ? a.id : null,
        emptyMessage: a == null
            ? (system == SystemAlbum.rejected
                  ? l10n.photosRejectedEmpty
                  : l10n.photosFavouritesEmpty)
            : l10n.photosAlbumEmpty,
      ),
    );
  }
}
