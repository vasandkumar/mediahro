import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/features/music/ui/tag_editor_screen.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Reloads [load] when the music index changes, at most once a second while
/// the indexer is writing.
class LibraryQuery<T> extends ConsumerStatefulWidget {
  const LibraryQuery({
    required this.load,
    required this.builder,
    this.queryKey,
    super.key,
  });

  final Future<T> Function(MusicLibrary library) load;
  final Widget Function(BuildContext context, T value) builder;

  /// Changing it reloads (sort order, filter).
  final Object? queryKey;

  @override
  ConsumerState<LibraryQuery<T>> createState() => _LibraryQueryState<T>();
}

class _LibraryQueryState<T> extends ConsumerState<LibraryQuery<T>> {
  T? _value;
  bool _loading = false;
  bool _again = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(LibraryQuery<T> old) {
    super.didUpdateWidget(old);
    if (old.queryKey != widget.queryKey) unawaited(_reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    _last = DateTime.now();
    try {
      final v = await widget.load(ref.read(musicLibraryProvider));
      if (mounted) setState(() => _value = v);
    } finally {
      _loading = false;
      if (_again && mounted) {
        _again = false;
        unawaited(_reload());
      }
    }
  }

  void _changed() {
    final wait = const Duration(seconds: 1) - DateTime.now().difference(_last);
    if (wait <= Duration.zero) {
      unawaited(_reload());
    } else {
      _timer ??= Timer(wait, () {
        _timer = null;
        unawaited(_reload());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(musicLibraryChangesProvider, (_, _) => _changed());
    final v = _value;
    if (v == null) {
      // Clipped: tabs and sheets can be shorter than the skeleton.
      return const ClipRect(
        child: SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          child: KSkeletonRows(),
        ),
      );
    }
    return widget.builder(context, v);
  }
}

// ------------------------------------------------------------ navigation --

TrackNavigation musicNavigation(BuildContext context) => (
  toAlbum: (t) {
    final key = t.albumKey;
    if (key != null) openAlbum(context, key, t.album!);
  },
  toArtist: (t) {
    final name = t.artist ?? t.albumArtist;
    if (name != null) openGroup(context, GroupField.artist, name);
  },
);

void openAlbum(BuildContext context, String groupKey, String title) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumScreen(groupKey: groupKey, title: title),
      ),
    );

void openGroup(BuildContext context, GroupField field, String value) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupScreen(field: field, value: value),
      ),
    );

// ------------------------------------------------------------------ tabs --

/// All songs with sorting (MUS-001).
class SongsTab extends ConsumerStatefulWidget {
  const SongsTab({super.key});

  @override
  ConsumerState<SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends ConsumerState<SongsTab> {
  SongSort _sort = SongSort.title;
  bool _desc = false;

  @override
  Widget build(BuildContext context) {
    final playingId = ref.watch(
      musicPlayerStateProvider.select((s) => s.value?.current?.itemId),
    );
    return LibraryQuery<List<MusicTrack>>(
      queryKey: (_sort, _desc),
      load: (lib) => lib.songs(sort: _sort, descending: _desc),
      builder: (context, songs) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(child: PlayShuffleBar(tracks: songs)),
                SortMenu<SongSort>(
                  values: SongSort.values,
                  current: _sort,
                  descending: _desc,
                  onChanged: (s, {required descending}) => setState(() {
                    _sort = s;
                    _desc = descending;
                  }),
                ),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) => TrackRow(
              track: songs[i],
              playing: songs[i].itemId == playingId,
              navigation: musicNavigation(context),
              onTap: () => unawaited(
                ref.read(musicPlayerProvider).playTracks(songs, start: i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Album grid with sorting (MUS-001).
class AlbumsTab extends StatefulWidget {
  const AlbumsTab({super.key});

  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab> {
  AlbumSort _sort = AlbumSort.title;
  bool _desc = false;

  @override
  Widget build(BuildContext context) => LibraryQuery<List<MusicAlbum>>(
    queryKey: (_sort, _desc),
    load: (lib) => lib.albums(sort: _sort, descending: _desc),
    builder: (context, albums) => Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SortMenu<AlbumSort>(
            values: AlbumSort.values,
            current: _sort,
            descending: _desc,
            onChanged: (s, {required descending}) => setState(() {
              _sort = s;
              _desc = descending;
            }),
          ),
        ),
        Expanded(child: AlbumGrid(albums: albums)),
      ],
    ),
  );
}

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({required this.albums, this.shrinkWrap = false, super.key});

  final List<MusicAlbum> albums;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KGrid(
      itemCount: albums.length,
      minTileWidth: 150,
      childAspectRatio: 0.78,
      itemBuilder: (context, i) {
        final a = albums[i];
        final artist = albumArtistLine(l10n, a);
        return KGridTile(
          semanticLabel: l10n.musicArtistAndAlbum(artist, a.title),
          artwork: CoverArt(itemId: a.coverItemId, radius: 0),
          title: a.title,
          subtitle: a.year == null
              ? artist
              : l10n.musicArtistAndYear(artist, '${a.year}'),
          onTap: () => openAlbum(context, a.groupKey, a.title),
        );
      },
    );
  }
}

/// Artists, album artists, genres, composers or years (MUS-001).
class GroupsTab extends StatelessWidget {
  const GroupsTab({required this.field, super.key});

  final GroupField field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LibraryQuery<List<MusicGroup>>(
      queryKey: field,
      load: (lib) => lib.groups(field),
      builder: (context, groups) => ListView.builder(
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          return KRow(
            title: g.name,
            subtitle:
                field == GroupField.artist || field == GroupField.albumArtist
                ? l10n.musicArtistAndAlbum(
                    l10n.musicAlbumCount(g.albumCount),
                    l10n.musicSongCount(g.trackCount),
                  )
                : l10n.musicSongCount(g.trackCount),
            leading: CoverArt(
              itemId: g.coverItemId,
              size: 48,
              radius:
                  field == GroupField.artist || field == GroupField.albumArtist
                  ? 24
                  : 6,
            ),
            onTap: () => openGroup(context, field, g.name),
          );
        },
      ),
    );
  }
}

/// Sources, then folders, then the music in them (MUS-001 folder view).
class FoldersTab extends ConsumerWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourceSummariesProvider).value ?? const [];
    final family = Theme.of(context).family;
    return ListView(
      children: [
        for (final s in sources)
          KRow(
            title: s.source.name,
            leading: Icon(KIcon.folder.resolve(family)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FolderScreen(
                  sourceId: s.source.id,
                  path: '',
                  title: s.source.name,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- screens --

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({required this.groupKey, required this.title, super.key});

  final String groupKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final playingId = ref.watch(
      musicPlayerStateProvider.select((s) => s.value?.current?.itemId),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: l10n.musicEditTags,
            icon: Icon(KIcon.edit.resolve(theme.family)),
            onPressed: () async {
              final tracks = await ref
                  .read(musicLibraryProvider)
                  .albumTracks(groupKey);
              if (context.mounted) await openTagEditor(context, tracks);
            },
          ),
        ],
      ),
      body: LibraryQuery<List<MusicTrack>>(
        queryKey: groupKey,
        load: (lib) => lib.albumTracks(groupKey),
        builder: (context, tracks) {
          if (tracks.isEmpty) {
            return KEmptyState(message: l10n.musicFolderEmpty);
          }
          final first = tracks.first;
          final total = tracks.fold<Duration>(
            Duration.zero,
            (a, t) => a + (t.duration ?? Duration.zero),
          );
          final artists = {for (final t in tracks) t.artist}.length;
          final artist =
              first.albumArtist ??
              (artists > 1
                  ? l10n.musicVariousArtists
                  : trackArtist(l10n, first));
          final discs = {for (final t in tracks) t.discNumber ?? 1};
          final rows = <Widget>[];
          int? disc;
          for (var i = 0; i < tracks.length; i++) {
            final t = tracks[i];
            if (discs.length > 1 && (t.discNumber ?? 1) != disc) {
              disc = t.discNumber ?? 1;
              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KSpacing.s16,
                    KSpacing.s16,
                    KSpacing.s16,
                    KSpacing.s4,
                  ),
                  child: Text(
                    l10n.musicDisc(disc),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              );
            }
            rows.add(
              TrackRow(
                track: t,
                showArt: false,
                showNumber: true,
                playing: t.itemId == playingId,
                subtitle: artists > 1 ? trackArtist(l10n, t) : null,
                navigation: (
                  toAlbum: null,
                  toArtist: musicNavigation(context).toArtist,
                ),
                onTap: () => unawaited(
                  ref.read(musicPlayerProvider).playTracks(tracks, start: i),
                ),
              ),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(KSpacing.s16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoverArt(
                      itemId: first.itemId,
                      size: 140,
                      semanticLabel: l10n.musicCoverOf(title),
                    ),
                    const SizedBox(width: KSpacing.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleLarge),
                          const SizedBox(height: KSpacing.s4),
                          Text(
                            first.year == null
                                ? artist
                                : l10n.musicArtistAndYear(
                                    artist,
                                    '${first.year}',
                                  ),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: KSpacing.s4),
                          Text(
                            l10n.musicAlbumSummary(
                              l10n.musicSongCount(tracks.length),
                              formatMediaDuration(total),
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PlayShuffleBar(tracks: tracks),
              ...rows,
              const SizedBox(height: 96),
            ],
          );
        },
      ),
    );
  }
}

/// An artist (albums, then every song), genre, composer or year.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({required this.field, required this.value, super.key});

  final GroupField field;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final playingId = ref.watch(
      musicPlayerStateProvider.select((s) => s.value?.current?.itemId),
    );
    final isArtist =
        field == GroupField.artist || field == GroupField.albumArtist;
    return Scaffold(
      appBar: AppBar(
        title: Text(value),
        actions: [
          IconButton(
            tooltip: l10n.musicEditTags,
            icon: Icon(KIcon.edit.resolve(theme.family)),
            onPressed: () async {
              final tracks = await ref
                  .read(musicLibraryProvider)
                  .groupTracks(field, value);
              if (context.mounted) await openTagEditor(context, tracks);
            },
          ),
        ],
      ),
      body: LibraryQuery<(List<MusicAlbum>, List<MusicTrack>)>(
        queryKey: (field, value),
        load: (lib) async => (
          isArtist
              ? await lib.albums(artist: value, sort: AlbumSort.year)
              : <MusicAlbum>[],
          await lib.groupTracks(field, value),
        ),
        builder: (context, data) {
          final (albums, tracks) = data;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: PlayShuffleBar(tracks: tracks)),
              if (albums.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KSpacing.s16,
                      KSpacing.s8,
                      KSpacing.s16,
                      KSpacing.s8,
                    ),
                    child: Text(
                      l10n.musicAlbumsSection,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 210,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: KSpacing.s16,
                      ),
                      itemCount: albums.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: KSpacing.s12),
                      itemBuilder: (context, i) {
                        final a = albums[i];
                        return SizedBox(
                          width: 150,
                          child: KGridTile(
                            semanticLabel: a.title,
                            artwork: CoverArt(itemId: a.coverItemId, radius: 0),
                            title: a.title,
                            subtitle: a.year?.toString(),
                            onTap: () =>
                                openAlbum(context, a.groupKey, a.title),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KSpacing.s16,
                      KSpacing.s16,
                      KSpacing.s16,
                      KSpacing.s8,
                    ),
                    child: Text(
                      l10n.musicSongsSection,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
              SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (context, i) => TrackRow(
                  track: tracks[i],
                  playing: tracks[i].itemId == playingId,
                  navigation: (
                    toAlbum: musicNavigation(context).toAlbum,
                    toArtist: isArtist
                        ? null
                        : musicNavigation(context).toArtist,
                  ),
                  onTap: () => unawaited(
                    ref.read(musicPlayerProvider).playTracks(tracks, start: i),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          );
        },
      ),
    );
  }
}

/// One folder of a source: sub-folders with music, then its songs.
class FolderScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final family = Theme.of(context).family;
    final views = ref.watch(libraryViewsProvider);
    final playingId = ref.watch(
      musicPlayerStateProvider.select((s) => s.value?.current?.itemId),
    );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: LibraryQuery<(List<FolderEntry>, List<MusicTrack>)>(
        queryKey: (sourceId, path),
        load: (lib) async => (
          await views.folders(sourceId, path, LibraryMode.music),
          await lib.folderTracks(sourceId, path),
        ),
        builder: (context, data) {
          final (folders, tracks) = data;
          if (folders.isEmpty && tracks.isEmpty) {
            return KEmptyState(message: l10n.musicFolderEmpty);
          }
          return ListView(
            children: [
              for (final f in folders)
                KRow(
                  title: f.name,
                  subtitle: l10n.musicSongCount(f.itemCount),
                  leading: Icon(KIcon.folder.resolve(family)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FolderScreen(
                        sourceId: sourceId,
                        path: f.path,
                        title: f.name,
                      ),
                    ),
                  ),
                ),
              if (tracks.isNotEmpty) PlayShuffleBar(tracks: tracks),
              for (var i = 0; i < tracks.length; i++)
                TrackRow(
                  track: tracks[i],
                  playing: tracks[i].itemId == playingId,
                  navigation: musicNavigation(context),
                  onTap: () => unawaited(
                    ref.read(musicPlayerProvider).playTracks(tracks, start: i),
                  ),
                ),
              const SizedBox(height: 96),
            ],
          );
        },
      ),
    );
  }
}

/// Sort field and direction picker.
class SortMenu<T extends Enum> extends StatelessWidget {
  const SortMenu({
    required this.values,
    required this.current,
    required this.descending,
    required this.onChanged,
    super.key,
  });

  final List<T> values;
  final T current;
  final bool descending;
  final void Function(T sort, {required bool descending}) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<Object>(
      tooltip: l10n.musicSort,
      icon: const Icon(Icons.sort),
      onSelected: (v) => v is T
          ? onChanged(v, descending: descending)
          : onChanged(current, descending: !descending),
      itemBuilder: (_) => [
        for (final v in values)
          CheckedPopupMenuItem<Object>(
            value: v,
            checked: v == current,
            child: Text(l10n.musicSortBy(v.name)),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: false,
          checked: descending,
          child: Text(l10n.musicSortReverse),
        ),
      ],
    );
  }
}
