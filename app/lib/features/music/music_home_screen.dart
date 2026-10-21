import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/alarms_screen.dart';
import 'package:mediahro/features/music/ui/books_tab.dart';
import 'package:mediahro/features/music/ui/extras.dart';
import 'package:mediahro/features/music/ui/library_screens.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro/features/music/ui/playlists.dart';
import 'package:mediahro/features/music/ui/podcasts_tab.dart';
import 'package:mediahro/features/music/ui/radio_tab.dart';
import 'package:mediahro/features/music/ui/scrobble_settings.dart';
import 'package:mediahro/ui/pending_screen.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The Music destination (MUS-001): songs, albums, artists, album artists,
/// genres, composers, years and folders, over B2's index. Starts the
/// background tag reader (MUS-002) and art cache (MUS-004).
class MusicHomeScreen extends ConsumerWidget {
  const MusicHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(musicLibraryAvailableProvider)
      ? const _MusicHome()
      // No library database (shell-only builds and tests): the pending
      // placeholder the shell showed before M4.
      : PendingScreen(
          title: AppLocalizations.of(context).appNavMusic,
          milestone: 'M4',
        );
}

class _MusicHome extends ConsumerStatefulWidget {
  const _MusicHome();

  @override
  ConsumerState<_MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends ConsumerState<_MusicHome> {
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
      (l10n.musicTabPlaylists, const PlaylistsTab()),
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
      (l10n.musicTabPodcasts, const PodcastsTab()),
      (l10n.musicTabBooks, const BooksTab()),
      (l10n.musicTabRadio, const RadioTab()),
    ];
    final songs = _songs;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).appNavMusic),
          actions: [
            PopupMenuButton<String>(
              tooltip: l10n.musicMoreNowPlaying,
              onSelected: (v) async {
                switch (v) {
                  case 'sound':
                    showSoundSheet(context);
                  case 'alarms':
                    await openAlarms(context);
                  case 'scrobble':
                    await openScrobbleSettings(context);
                  case 'undoTags':
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    await ref.read(tagEditorProvider).undoLast();
                    messenger?.showSnackBar(
                      SnackBar(content: Text(l10n.musicTagUndone)),
                    );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'sound', child: Text(l10n.musicSound)),
                PopupMenuItem(value: 'alarms', child: Text(l10n.musicAlarms)),
                PopupMenuItem(
                  value: 'scrobble',
                  child: Text(l10n.musicScrobbling),
                ),
                PopupMenuItem(
                  value: 'undoTags',
                  child: Text(l10n.musicTagUndo),
                ),
              ],
            ),
            if (ref.watch(
              musicPlayerStateProvider.select((s) => s.value?.current != null),
            ))
              IconButton(
                tooltip: l10n.musicQueue,
                icon: const Icon(Icons.queue_music),
                onPressed: () => showQueueSheet(context),
              ),
          ],
          bottom: TabBar(
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
              child: songs == null
                  ? const SizedBox.shrink()
                  : TabBarView(children: [for (final (_, view) in tabs) view]),
            ),
          ],
        ),
      ),
    );
  }
}
