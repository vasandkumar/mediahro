import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart' show DownloadState;
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro/features/music/ui/podcasts_tab.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// One subscribed show (POD-002): its episodes with where the listener is
/// and what is downloaded, and the show's own choices.
class PodcastScreen extends ConsumerWidget {
  const PodcastScreen({required this.showId, super.key});

  final String showId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final show = ref.watch(podcastShowProvider(showId)).value;
    final episodes = ref.watch(podcastEpisodesProvider(showId)).value;
    if (show == null) {
      return Scaffold(
        appBar: AppBar(),
        body: episodes == null
            ? const KSkeletonRows()
            : KEmptyState(message: l10n.musicPodNoEpisodes),
      );
    }
    final service = ref.read(podcastServiceProvider);
    final playing = ref.watch(
      podcastPlayerStateProvider.select((s) => s.value?.episode?.guid),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(show.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l10n.musicPodRefreshAll,
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final r = await service.refresh(show.id);
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    r.ok
                        ? l10n.musicPodNewEpisodes(r.added)
                        : podcastFailureText(l10n, r.failure!),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: l10n.musicPodSettings,
            icon: const Icon(Icons.tune),
            onPressed: () => showShowSettings(context, ref, show),
          ),
        ],
      ),
      body: episodes == null
          ? const KSkeletonRows()
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(KSpacing.s16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShowArt(path: show.artPath, size: 96),
                      const SizedBox(width: KSpacing.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(show.title, style: theme.textTheme.titleLarge),
                            if (show.author != null)
                              Text(
                                show.author!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (show.description != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: KSpacing.s8,
                                ),
                                child: Text(
                                  show.description!,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (episodes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(KSpacing.s24),
                    child: Center(child: Text(l10n.musicPodNoEpisodes)),
                  ),
                for (final e in episodes)
                  EpisodeTile(
                    show: show,
                    entry: e,
                    playing: e.episode.guid == playing,
                  ),
                const SizedBox(height: 96),
              ],
            ),
    );
  }
}

/// Plays [episode] of [show] and opens the player.
Future<void> playEpisode(
  BuildContext context,
  WidgetRef ref,
  PodcastShow show,
  ParsedEpisode episode,
) async {
  await ref.read(podcastPlayerProvider).play(show, episode);
  if (context.mounted) openNowPlaying(context);
}

class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({
    required this.show,
    required this.entry,
    required this.playing,
    super.key,
  });

  final PodcastShow show;
  final EpisodeEntry entry;
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final service = ref.read(podcastServiceProvider);
    final e = entry.episode;
    final locale = Localizations.localeOf(context).toString();
    final date = e.published == null
        ? null
        : DateFormat.yMMMd(locale).format(e.published!.toLocal());
    final info = date != null && e.duration != null
        ? l10n.musicPodEpisodeInfo(date, formatDuration(e.duration!))
        : date ?? (e.duration == null ? null : formatDuration(e.duration!));
    final p = entry.progress;
    final dl = entry.download;
    final fraction = e.duration == null || e.duration!.inMilliseconds == 0
        ? null
        : (p.position.inMilliseconds / e.duration!.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    return Semantics(
      selected: playing,
      child: InkWell(
        onTap: () => unawaited(playEpisode(context, ref, show, e)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KSpacing.s16,
              vertical: KSpacing.s8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: entry.played
                              ? FontWeight.normal
                              : FontWeight.w600,
                          color: playing
                              ? theme.colorScheme.primary
                              : entry.played
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                      if (info != null)
                        Text(info, style: theme.textTheme.bodySmall),
                      if (p.started && !entry.played && fraction != null)
                        Padding(
                          padding: const EdgeInsets.only(top: KSpacing.s4),
                          child: ExcludeSemantics(
                            child: LinearProgressIndicator(value: fraction),
                          ),
                        ),
                      if (_status(l10n, entry) case final String s)
                        Text(s, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (dl != null && dl.done)
                  Icon(
                    Icons.download_done,
                    size: 20,
                    semanticLabel: l10n.musicPodDownloaded,
                  ),
                PopupMenuButton<String>(
                  tooltip: l10n.musicMoreActions(e.title),
                  onSelected: (v) async {
                    switch (v) {
                      case 'play':
                        await playEpisode(context, ref, show, e);
                      case 'download':
                        await service.download(show, e);
                      case 'remove':
                        await service.removeDownload(e);
                      case 'played':
                        await service.markPlayed(show.id, [
                          e.guid,
                        ], played: !entry.played);
                      case 'notes':
                        if (context.mounted) showEpisodeNotes(context, e);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'play', child: Text(l10n.musicPlay)),
                    if (dl == null || dl.state == DownloadState.failed)
                      PopupMenuItem(
                        value: 'download',
                        child: Text(l10n.musicPodDownload),
                      )
                    else
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(l10n.musicPodRemoveDownload),
                      ),
                    PopupMenuItem(
                      value: 'played',
                      child: Text(
                        entry.played
                            ? l10n.musicPodMarkUnplayed
                            : l10n.musicPodMarkPlayed,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'notes',
                      child: Text(l10n.musicPodShowNotes),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The line under an episode that is played or on its way to the device.
  static String? _status(AppLocalizations l10n, EpisodeEntry e) {
    final d = e.download;
    if (d != null) {
      switch (d.state) {
        case DownloadState.queued || DownloadState.paused:
          return l10n.musicPodDownloadQueued;
        case DownloadState.running:
          final f = d.fraction;
          return f == null
              ? l10n.musicPodDownloadQueued
              : l10n.musicPodDownloading((f * 100).round());
        case DownloadState.failed:
          return l10n.musicPodDownloadFailed;
        case DownloadState.done || DownloadState.expired:
          break;
      }
    }
    return e.played ? l10n.musicPodPlayed : null;
  }
}

void showEpisodeNotes(BuildContext context, ParsedEpisode e) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.7,
      child: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          Text(e.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: KSpacing.s12),
          SelectableText(
            e.description ?? AppLocalizations.of(context).musicPodNoNotes,
          ),
        ],
      ),
    ),
  ),
);

/// Order, automatic downloads, deleting what is played, mark all, and
/// unsubscribing.
void showShowSettings(BuildContext context, WidgetRef ref, PodcastShow show) =>
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        // Above the shell's bottom bar.
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ShowSettings(
          showId: show.id,
          // The show's own screen is in the shell's navigator.
          closeShow: () => Navigator.of(context).pop(),
        ),
      ),
    );

class _ShowSettings extends ConsumerWidget {
  const _ShowSettings({required this.showId, required this.closeShow});

  final String showId;
  final VoidCallback closeShow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final show = ref.watch(podcastShowProvider(showId)).value;
    final service = ref.read(podcastServiceProvider);
    if (show == null) return const SizedBox.shrink();
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          SwitchListTile(
            title: Text(l10n.musicPodOldestFirst),
            value: show.oldestFirst,
            onChanged: (v) =>
                unawaited(service.configure(show.id, oldestFirst: v)),
          ),
          ListTile(
            title: Text(l10n.musicPodAutoDownload),
            subtitle: Text(l10n.musicPodAutoDownloadNote),
            trailing: DropdownButton<int>(
              value: const [0, 1, 3, 5].contains(show.autoDownload)
                  ? show.autoDownload
                  : 0,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(l10n.musicPodAutoDownloadOff),
                ),
                for (final n in const [1, 3, 5])
                  DropdownMenuItem(
                    value: n,
                    child: Text(l10n.musicPodAutoDownloadCount(n)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) {
                  unawaited(service.configure(show.id, autoDownload: v));
                }
              },
            ),
          ),
          SwitchListTile(
            title: Text(l10n.musicPodDeleteWhenPlayed),
            value: show.deleteWhenPlayed,
            onChanged: (v) =>
                unawaited(service.configure(show.id, deleteWhenPlayed: v)),
          ),
          ListTile(
            title: Text(l10n.musicPodMarkAllPlayed),
            onTap: () {
              unawaited(service.markAllPlayed(show.id, played: true));
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            title: Text(l10n.musicPodMarkAllUnplayed),
            onTap: () {
              unawaited(service.markAllPlayed(show.id, played: false));
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            title: Text(
              l10n.musicPodUnsubscribe,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              final nav = Navigator.of(context);
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  content: Text(l10n.musicPodUnsubscribeConfirm(show.title)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(d).pop(false),
                      child: Text(l10n.musicCancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(d).pop(true),
                      child: Text(l10n.musicPodUnsubscribe),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              await service.unsubscribe(show.id);
              // The sheet, then the show's own screen.
              nav.pop();
              closeShow();
            },
          ),
        ],
      ),
    );
  }
}
