import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/library_screens.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The Music destination (MUS-001): songs, albums, artists, album artists,
/// genres, composers, years and folders, over B2's index. Starts the
/// background tag reader (MUS-002) and art cache (MUS-004).
class MusicHomeScreen extends ConsumerStatefulWidget {
  const MusicHomeScreen({super.key});

  @override
  ConsumerState<MusicHomeScreen> createState() => _MusicHomeScreenState();
}

class _MusicHomeScreenState extends ConsumerState<MusicHomeScreen> {
  int? _songs;
  int _pending = 0;
  StreamSubscription<int>? _progress;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final indexer = ref.read(musicIndexerProvider);
    _progress = indexer.completed.listen((_) => _refreshPending());
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshPending(),
    );
    unawaited(_count());
  }

  @override
  void dispose() {
    unawaited(_progress?.cancel());
    _poll?.cancel();
    super.dispose();
  }

  void _refreshPending() {
    final p = ref.read(musicIndexerProvider).pending;
    if (p != _pending && mounted) setState(() => _pending = p);
  }

  Future<void> _count() async {
    final n = await ref.read(musicLibraryProvider).songCount();
    if (mounted && n != _songs) setState(() => _songs = n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref
      ..listen(musicLibraryChangesProvider, (_, _) => unawaited(_count()))
      // Keeps the player (and its media session) alive with the screen.
      ..watch(musicPlayerProvider);
    final tabs = <(String, Widget)>[
      (l10n.musicTabSongs, const SongsTab()),
      (l10n.musicTabAlbums, const AlbumsTab()),
      (l10n.musicTabArtists, const GroupsTab(field: GroupField.artist)),
      (
        l10n.musicTabAlbumArtists,
        const GroupsTab(field: GroupField.albumArtist),
      ),
      (l10n.musicTabGenres, const GroupsTab(field: GroupField.genre)),
      (l10n.musicTabComposers, const GroupsTab(field: GroupField.composer)),
      (l10n.musicTabYears, const GroupsTab(field: GroupField.year)),
      (l10n.musicTabFolders, const FoldersTab()),
    ];
    final songs = _songs;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).appNavMusic),
          actions: [
            if (ref.watch(
              musicPlayerStateProvider.select((s) => s.value?.current != null),
            ))
              IconButton(
                tooltip: l10n.musicQueue,
                icon: const Icon(Icons.queue_music),
                onPressed: () => showQueueSheet(context),
              ),
          ],
          bottom: songs == 0
              ? null
              : TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final (label, _) in tabs) Tab(text: label)],
                ),
        ),
        body: Column(
          children: [
            if (_pending > 0)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpacing.s16,
                    vertical: KSpacing.s4,
                  ),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: KSpacing.s8),
                      Expanded(child: Text(l10n.musicIndexing(_pending))),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: switch (songs) {
                null => const KSkeletonRows(),
                0 => KEmptyState(
                  title: l10n.musicEmptyTitle,
                  message: l10n.musicEmptyMessage,
                  actions: [
                    FilledButton(
                      onPressed: () => context.go('/sources?add=folder'),
                      child: Text(l10n.musicAddMusic),
                    ),
                  ],
                ),
                _ => TabBarView(children: [for (final (_, view) in tabs) view]),
              },
            ),
          ],
        ),
      ),
    );
  }
}
