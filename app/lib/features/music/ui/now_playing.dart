import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart' show QueueRow;
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/ui/library_screens.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Opens Now Playing above the shell (it covers the bar and mini player).
void openNowPlaying(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const NowPlayingScreen(),
      ),
    );

/// Now Playing (MUS-006): art, progress, transport, shuffle/repeat, queue,
/// "go to album/artist", swipe gestures and a landscape/tablet layout.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(musicPlayerStateProvider).value;
    final player = ref.read(musicPlayerProvider);
    final t = s?.current;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.musicClose,
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.musicNowPlaying),
        actions: [
          if (t != null)
            IconButton(
              tooltip: l10n.musicQueue,
              icon: const Icon(Icons.queue_music),
              onPressed: () => showQueueSheet(context),
            ),
        ],
      ),
      body: s == null || t == null
          ? KEmptyState(message: l10n.musicNothingPlaying)
          : GestureDetector(
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 600) {
                  Navigator.of(context).maybePop();
                }
              },
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth > c.maxHeight * 1.1;
                    final art = _SwipeArt(track: t, player: player);
                    final controls = _Controls(state: s, player: player);
                    if (wide) {
                      return Padding(
                        padding: const EdgeInsets.all(KSpacing.s24),
                        child: Row(
                          children: [
                            Flexible(child: Center(child: art)),
                            const SizedBox(width: KSpacing.s32),
                            Expanded(child: Center(child: controls)),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KSpacing.s24,
                        vertical: KSpacing.s16,
                      ),
                      child: Column(
                        children: [
                          Expanded(child: Center(child: art)),
                          const SizedBox(height: KSpacing.s24),
                          controls,
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// Cover art; swiping it sideways skips tracks.
class _SwipeArt extends StatelessWidget {
  const _SwipeArt({required this.track, required this.player});

  final MusicTrack track;
  final MusicPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -400) unawaited(player.next());
        if (v > 400) unawaited(player.previous());
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
        child: AspectRatio(
          aspectRatio: 1,
          child: CoverArt(
            itemId: track.itemId,
            radius: 16,
            semanticLabel: l10n.musicCoverOf(
              track.album ?? l10n.musicUnknownAlbum,
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.player});

  final MusicPlayerState state;
  final MusicPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = state.current!;
    final duration = state.duration ?? Duration.zero;
    final error = state.playback.error;
    final artist = t.artist ?? t.albumArtist;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.title,
          style: theme.textTheme.headlineSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: KSpacing.s4),
        _LinkText(
          text: artist ?? l10n.musicUnknownArtist,
          label: l10n.musicGoToArtist,
          onTap: artist == null
              ? null
              : () => _go(
                  context,
                  (ctx) => openGroup(ctx, GroupField.artist, artist),
                ),
        ),
        if (t.album != null)
          _LinkText(
            text: t.album!,
            label: l10n.musicGoToAlbum,
            onTap: () =>
                _go(context, (ctx) => openAlbum(ctx, t.albumKey!, t.album!)),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: KSpacing.s8),
            child: Text(
              l10n.musicError(error.code.name),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: KSpacing.s16),
        Semantics(
          label: l10n.musicPosition(
            formatMediaDuration(state.position),
            formatMediaDuration(duration),
          ),
          child: KSeekBar(
            position: state.position,
            duration: duration,
            onSeek: (p) => unawaited(player.seek(p)),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatMediaDuration(state.position)),
            Text(formatMediaDuration(duration)),
          ],
        ),
        const SizedBox(height: KSpacing.s8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: state.shuffle
                  ? l10n.musicShuffleOn
                  : l10n.musicShuffleOff,
              isSelected: state.shuffle,
              icon: const Icon(Icons.shuffle),
              selectedIcon: Icon(
                Icons.shuffle_on_outlined,
                color: theme.colorScheme.primary,
              ),
              onPressed: () =>
                  unawaited(player.setShuffle(enabled: !state.shuffle)),
            ),
            KIconButton(
              icon: KIcon.previous,
              label: l10n.musicPreviousLabel,
              size: 36,
              onPressed: () => unawaited(player.previous()),
            ),
            IconButton.filled(
              tooltip: state.playing
                  ? l10n.musicPauseLabel
                  : l10n.musicPlayLabel,
              iconSize: 44,
              icon: Icon(
                (state.playing ? KIcon.pause : KIcon.play).resolve(
                  theme.family,
                ),
              ),
              onPressed: () => unawaited(player.togglePlayPause()),
            ),
            KIconButton(
              icon: KIcon.next,
              label: l10n.musicNextLabel,
              size: 36,
              onPressed: state.hasNext ? () => unawaited(player.next()) : null,
            ),
            IconButton(
              tooltip: l10n.musicRepeat(state.repeat.name),
              isSelected: state.repeat != RepeatMode.off,
              icon: Icon(
                state.repeat == RepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
              ),
              selectedIcon: Icon(
                state.repeat == RepeatMode.one
                    ? Icons.repeat_one_on_outlined
                    : Icons.repeat_on_outlined,
                color: theme.colorScheme.primary,
              ),
              onPressed: () => unawaited(
                player.setRepeat(switch (state.repeat) {
                  RepeatMode.off => RepeatMode.all,
                  RepeatMode.all => RepeatMode.one,
                  RepeatMode.one => RepeatMode.off,
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Leaves Now Playing, then navigates in the shell.
  void _go(BuildContext context, void Function(BuildContext) open) {
    final nav = Navigator.of(context);
    open(nav.context);
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.text, required this.label, this.onTap});

  final String text;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: onTap != null,
      hint: onTap == null ? null : label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The queue (MUS-007): reorder, remove, jump.
void showQueueSheet(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 0.85, child: QueueView()),
  ),
);

class QueueView extends ConsumerWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(musicPlayerStateProvider).value;
    final player = ref.read(musicPlayerProvider);
    final queues = s?.queues ?? const <QueueRow>[];
    final currentId = s?.queueId;
    final current = queues.where((q) => q.id == currentId).firstOrNull;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
            child: Row(
              children: [
                Expanded(
                  child: queues.length > 1 && current != null
                      ? DropdownButton<int>(
                          isExpanded: true,
                          value: current.id,
                          underline: const SizedBox.shrink(),
                          style: Theme.of(context).textTheme.titleLarge,
                          hint: Text(l10n.musicSwitchQueue),
                          items: [
                            for (final q in queues)
                              DropdownMenuItem(
                                value: q.id,
                                child: Text(queueName(l10n, q)),
                              ),
                          ],
                          onChanged: (id) {
                            if (id != null) unawaited(player.switchQueue(id));
                          },
                        )
                      : Text(
                          current == null
                              ? l10n.musicQueue
                              : queueName(l10n, current),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                ),
                _QueueMenu(state: s, player: player),
              ],
            ),
          ),
          TabBar(
            tabs: [
              Tab(text: l10n.musicUpNext),
              Tab(text: l10n.musicHistory),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _UpNext(state: s, player: player),
                const _History(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Display name of a queue; the first one is created without a name.
String queueName(AppLocalizations l10n, QueueRow q) =>
    q.name == 'default' ? l10n.musicQueueDefaultName : q.name;

class _UpNext extends StatelessWidget {
  const _UpNext({required this.state, required this.player});

  final MusicPlayerState? state;
  final MusicPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = state;
    final queue = s?.queue ?? const <MusicTrack>[];
    if (s == null || queue.isEmpty) {
      return KEmptyState(message: l10n.musicQueueEmpty);
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorderItem: (from, to) => unawaited(player.move(from, to)),
      itemBuilder: (context, i) {
        final t = queue[i];
        return Dismissible(
          key: ValueKey('q$i-${t.itemId}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => unawaited(player.removeAt(i)),
          background: ColoredBox(
            color: Theme.of(context).colorScheme.errorContainer,
          ),
          child: KRow(
            title: t.title,
            subtitle: trackArtist(l10n, t),
            selected: i == s.index,
            leading: CoverArt(itemId: t.itemId, size: 44, radius: 6),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.musicRemoveFromQueue,
                  icon: Icon(KIcon.close.resolve(Theme.of(context).family)),
                  onPressed: () => unawaited(player.removeAt(i)),
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: Semantics(
                    label: l10n.musicReorderHandle(t.title),
                    child: const Padding(
                      padding: EdgeInsets.all(KSpacing.s12),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ],
            ),
            onTap: () => unawaited(player.jumpTo(i)),
          ),
        );
      },
    );
  }
}

/// Recently played songs (MUS-007 history); tapping one plays it next.
class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return LibraryQuery<List<(MusicTrack, DateTime)>>(
      load: (lib) => lib.history(),
      builder: (context, rows) => rows.isEmpty
          ? KEmptyState(message: l10n.musicHistoryEmpty)
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => TrackRow(
                track: rows[i].$1,
                onTap: () => unawaited(
                  ref.read(musicPlayerProvider).playNext([rows[i].$1]),
                ),
              ),
            ),
    );
  }
}

class _QueueMenu extends StatelessWidget {
  const _QueueMenu({required this.state, required this.player});

  final MusicPlayerState? state;
  final MusicPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = state;
    final current = s?.queues.where((q) => q.id == s.queueId).firstOrNull;
    return PopupMenuButton<String>(
      tooltip: l10n.musicQueueActions,
      icon: Icon(KIcon.more.resolve(Theme.of(context).family)),
      onSelected: (v) async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        switch (v) {
          case 'new':
            final name = await askName(
              context,
              title: l10n.musicNewQueue,
              label: l10n.musicQueueName,
              action: l10n.musicCreate,
            );
            if (name != null) {
              final id = await player.createQueue(name);
              await player.switchQueue(id);
            }
          case 'rename' when current != null:
            final name = await askName(
              context,
              title: l10n.musicRenameQueue,
              label: l10n.musicQueueName,
              action: l10n.musicSave,
              initial: queueName(l10n, current),
            );
            if (name != null) await player.renameQueue(current.id, name);
          case 'delete' when current != null:
            await player.deleteQueue(current.id);
          case 'playlist':
            final name = await askName(
              context,
              title: l10n.musicSaveAsPlaylist,
              label: l10n.musicPlaylistName,
              action: l10n.musicSave,
            );
            if (name != null && await player.saveAsPlaylist(name) != null) {
              messenger?.showSnackBar(
                SnackBar(content: Text(l10n.musicSavedAsPlaylist(name))),
              );
            }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'new', child: Text(l10n.musicNewQueue)),
        if (current != null)
          PopupMenuItem(value: 'rename', child: Text(l10n.musicRenameQueue)),
        if (current != null && (s?.queues.length ?? 0) > 1)
          PopupMenuItem(value: 'delete', child: Text(l10n.musicDeleteQueue)),
        if (s?.queue.isNotEmpty ?? false)
          PopupMenuItem(
            value: 'playlist',
            child: Text(l10n.musicSaveAsPlaylist),
          ),
      ],
    );
  }
}

/// A one-field name dialog; null when cancelled or blank.
Future<String?> askName(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String? initial,
}) async {
  final c = TextEditingController(text: initial);
  final l10n = AppLocalizations.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.of(d).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(),
          child: Text(l10n.musicCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(d).pop(c.text),
          child: Text(action),
        ),
      ],
    ),
  );
  c.dispose();
  final t = name?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// The shell's mini player (B3 slot, `miniPlayerSlotProvider`).
class MusicMiniPlayer extends ConsumerWidget {
  const MusicMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(musicPlayerStateProvider).value;
    final t = s?.current;
    if (s == null || t == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final player = ref.read(musicPlayerProvider);
    final d = s.duration;
    return KMiniPlayer(
      title: t.title,
      subtitle: trackArtist(l10n, t),
      artwork: CoverArt(itemId: t.itemId, size: 40, radius: 6),
      playing: s.playing,
      onPlayPause: () => unawaited(player.togglePlayPause()),
      playLabel: l10n.musicPlayLabel,
      pauseLabel: l10n.musicPauseLabel,
      onOpen: () => openNowPlaying(context),
      openLabel: l10n.musicOpenNowPlaying,
      progress: d == null || d == Duration.zero
          ? null
          : (s.position.inMilliseconds / d.inMilliseconds).clamp(0, 1),
      onNext: s.hasNext ? () => unawaited(player.next()) : null,
      nextLabel: l10n.musicNextLabel,
    );
  }
}

/// Builder for `miniPlayerSlotProvider` (main.dart wiring).
Widget musicMiniPlayerSlot(BuildContext context) => const MusicMiniPlayer();

/// Engine error copy (docs/06 §8).
String musicErrorText(AppLocalizations l10n, EngineError e) =>
    l10n.musicError(e.code.name);
