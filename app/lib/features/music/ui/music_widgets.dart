import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/music/books/book_library.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/tag_editor_screen.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Cover art of an item (MUS-004) or a neutral placeholder, decoded at the
/// size it is shown.
class CoverArt extends ConsumerWidget {
  const CoverArt({
    required this.itemId,
    this.size,
    this.radius = 8,
    this.semanticLabel,
    super.key,
  });

  final int? itemId;

  /// Logical edge length; null fills the parent.
  final double? size;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = itemId;
    final path = id == null ? null : ref.watch(coverPathProvider(id)).value;
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget child;
    if (path != null) {
      child = LayoutBuilder(
        builder: (context, c) {
          final edge = size ?? (c.maxWidth.isFinite ? c.maxWidth : 300);
          return Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: (edge * dpr).round().clamp(32, 2048),
            gaplessPlayback: true,
            semanticLabel: semanticLabel,
            excludeFromSemantics: semanticLabel == null,
            errorBuilder: (_, _, _) => _placeholder(context, scheme),
          );
        },
      );
    } else {
      child = Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        child: _placeholder(context, scheme),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: AspectRatio(aspectRatio: 1, child: child),
      ),
    );
  }

  Widget _placeholder(BuildContext context, ColorScheme scheme) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        KIcon.music.resolve(Theme.of(context).family),
        color: scheme.onSurfaceVariant,
        size: (size ?? 96) * 0.4,
      ),
    ),
  );
}

String trackArtist(AppLocalizations l10n, MusicTrack t) =>
    t.artist ?? t.albumArtist ?? l10n.musicUnknownArtist;

String trackSubtitle(AppLocalizations l10n, MusicTrack t) => t.album == null
    ? trackArtist(l10n, t)
    : l10n.musicArtistAndAlbum(trackArtist(l10n, t), t.album!);

String albumArtistLine(AppLocalizations l10n, MusicAlbum a) =>
    a.displayArtist ??
    (a.isCompilation ? l10n.musicVariousArtists : l10n.musicUnknownArtist);

/// What a song row's menu can do; screens supply navigation.
typedef TrackNavigation = ({
  void Function(MusicTrack track)? toAlbum,
  void Function(MusicTrack track)? toArtist,
});

/// A song row (MUS-001): art or track number, title, artist · album,
/// duration, and the actions menu (MUS-007 play next / add to queue).
class TrackRow extends ConsumerWidget {
  const TrackRow({
    required this.track,
    required this.onTap,
    this.showArt = true,
    this.showNumber = false,
    this.subtitle,
    this.navigation,
    this.playing = false,
    super.key,
  });

  final MusicTrack track;
  final VoidCallback onTap;
  final bool showArt;
  final bool showNumber;
  final String? subtitle;
  final TrackNavigation? navigation;
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final d = track.duration;
    return KRow(
      title: track.title,
      subtitle: subtitle ?? trackSubtitle(l10n, track),
      selected: playing,
      leading: showArt
          ? CoverArt(itemId: track.itemId, size: 48, radius: 6)
          : showNumber
          ? SizedBox(
              width: 32,
              child: Text(
                track.trackNumber?.toString() ?? '',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d != null)
            Text(
              formatMediaDuration(d),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          TrackMenuButton(tracks: [track], navigation: navigation),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// The "more" menu for one or more songs.
class TrackMenuButton extends ConsumerWidget {
  const TrackMenuButton({required this.tracks, this.navigation, super.key});

  final List<MusicTrack> tracks;
  final TrackNavigation? navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final family = Theme.of(context).family;
    final single = tracks.length == 1 ? tracks.first : null;
    final toAlbum = navigation?.toAlbum;
    final toArtist = navigation?.toArtist;
    return PopupMenuButton<String>(
      tooltip: single == null
          ? l10n.musicQueue
          : l10n.musicMoreActions(single.title),
      icon: Icon(KIcon.more.resolve(family)),
      onSelected: (v) async {
        final player = ref.read(musicPlayerProvider);
        final messenger = ScaffoldMessenger.maybeOf(context);
        switch (v) {
          case 'next':
            await player.playNext(tracks);
            messenger?.showSnackBar(
              SnackBar(content: Text(l10n.musicAddedToQueue(tracks.length))),
            );
          case 'queue':
            await player.addToQueue(tracks);
            messenger?.showSnackBar(
              SnackBar(content: Text(l10n.musicAddedToQueue(tracks.length))),
            );
          case 'other':
            if (context.mounted) await addToAnotherQueue(context, ref, tracks);
          case 'tags':
            if (context.mounted) await openTagEditor(context, tracks);
          case 'book':
            await ref
                .read(bookStoreProvider)
                .setMark(BookLibrary.singleId(single!.itemId), 'book');
            ref.invalidate(bookEntriesProvider);
            messenger?.showSnackBar(
              SnackBar(content: Text(l10n.musicBookMarked(single.title))),
            );
          case 'album':
            toAlbum?.call(single!);
          case 'artist':
            toArtist?.call(single!);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'next', child: Text(l10n.musicPlayNext)),
        PopupMenuItem(value: 'queue', child: Text(l10n.musicAddToQueue)),
        PopupMenuItem(value: 'other', child: Text(l10n.musicAddToAnotherQueue)),
        PopupMenuItem(value: 'tags', child: Text(l10n.musicEditTags)),
        if (single != null)
          PopupMenuItem(value: 'book', child: Text(l10n.musicBookTreatAsBook)),
        if (single?.album != null && toAlbum != null)
          PopupMenuItem(value: 'album', child: Text(l10n.musicGoToAlbum)),
        if ((single?.artist ?? single?.albumArtist) != null && toArtist != null)
          PopupMenuItem(value: 'artist', child: Text(l10n.musicGoToArtist)),
      ],
    );
  }
}

/// Play and shuffle buttons above a list of songs.
class PlayShuffleBar extends ConsumerWidget {
  const PlayShuffleBar({required this.tracks, super.key});

  final List<MusicTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.read(musicPlayerProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.s16,
        vertical: KSpacing.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : () => unawaited(player.playTracks(tracks)),
              icon: Icon(KIcon.play.resolve(Theme.of(context).family)),
              label: Text(l10n.musicPlay),
            ),
          ),
          const SizedBox(width: KSpacing.s12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : () => unawaited(
                      player.playTracks(
                        tracks,
                        start: tracks.length > 1
                            ? DateTime.now().microsecond % tracks.length
                            : 0,
                        shuffle: true,
                      ),
                    ),
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.musicShuffle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks (or creates) a queue other than the playing one and appends
/// [tracks] to it (MUS-007 "add to another queue").
Future<void> addToAnotherQueue(
  BuildContext context,
  WidgetRef ref,
  List<MusicTrack> tracks,
) async {
  final l10n = AppLocalizations.of(context);
  final player = ref.read(musicPlayerProvider);
  final s = player.state;
  String nameOf(String n) => n == 'default' ? l10n.musicQueueDefaultName : n;
  final others = [
    for (final q in s.queues)
      if (q.id != s.queueId) q,
  ];
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picked = await showDialog<(int?, String)>(
    context: context,
    builder: (d) => SimpleDialog(
      title: Text(l10n.musicAddToAnotherQueue),
      children: [
        for (final q in others)
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop((q.id, q.name)),
            child: Text(nameOf(q.name)),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(d).pop((null, '')),
          child: Text(l10n.musicNewQueue),
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  var (id, name) = picked;
  if (id == null) {
    final c = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.musicNewQueue),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.musicQueueName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: Text(l10n.musicCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(c.text.trim()),
            child: Text(l10n.musicCreate),
          ),
        ],
      ),
    );
    c.dispose();
    if (typed == null || typed.isEmpty) return;
    name = typed;
    id = await player.createQueue(typed);
  }
  await player.addToQueueId(id, tracks);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(l10n.musicAddedToNamedQueue(tracks.length, nameOf(name))),
    ),
  );
}
