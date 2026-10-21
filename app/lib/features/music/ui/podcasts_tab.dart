import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/features/music/ui/podcast_screen.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The Podcasts tab (POD-002): the subscriptions with how much is unplayed,
/// add by feed address, OPML in and out, and a manual check for new
/// episodes. There is no directory and no recommendations.
class PodcastsTab extends ConsumerStatefulWidget {
  const PodcastsTab({super.key});

  @override
  ConsumerState<PodcastsTab> createState() => _PodcastsTabState();
}

class _PodcastsTabState extends ConsumerState<PodcastsTab> {
  bool _busy = false;

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final show = await showDialog<PodcastShow>(
      context: context,
      builder: (_) => const SubscribeDialog(),
    );
    if (show != null) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.musicPodSubscribed(show.title))),
      );
    }
  }

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final r = await ref.read(podcastServiceProvider).refreshAll();
      final added = r.fold<int>(0, (a, e) => a + e.added);
      final failed = r.where((e) => !e.ok).length;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            failed > 0
                ? l10n.musicPodRefreshFailed(failed)
                : l10n.musicPodNewEpisodes(added),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final storage = ref.read(storageProvider);
    final service = ref.read(podcastServiceProvider);
    final picked = await storage.pickFiles();
    if (picked.isEmpty) return;
    final String text;
    try {
      text = utf8.decode(
        await readPickedFile(storage, picked.first.uri, maxBytes: 8 << 20),
        allowMalformed: true,
      );
    } on Exception {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.musicPodImportNone)));
      return;
    }
    if (!mounted) return;
    final progress = ValueNotifier<(int, int)>((0, 0));
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (context, p, _) => AlertDialog(
            content: Row(
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: KSpacing.s16),
                Expanded(child: Text(l10n.musicPodImporting(p.$1, p.$2))),
              ],
            ),
          ),
        ),
      ),
    );
    final r = await service.importOpml(
      text,
      onProgress: (d, t) => progress.value = (d, t),
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          r.added + r.alreadySubscribed + r.failed.length == 0
              ? l10n.musicPodImportNone
              : l10n.musicPodImported(
                  r.added,
                  r.alreadySubscribed,
                  r.failed.length,
                ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    final opml = await ref.read(podcastServiceProvider).exportOpml();
    await ref
        .read(storageProvider)
        .saveFile(
          suggestedName: 'Mediahro podcasts.opml',
          mimeType: 'text/x-opml',
          content: Stream.value(utf8.encode(opml)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(podcastShowsProvider);
    final shows = async.value;
    if (shows == null) return const KSkeletonRows();
    final toolbar = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.s16,
        vertical: KSpacing.s8,
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: () => unawaited(_add()),
            icon: const Icon(Icons.add),
            label: Text(l10n.musicPodAdd),
          ),
          const Spacer(),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(KSpacing.s8),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: l10n.musicPodSettings,
            onSelected: (v) => unawaited(switch (v) {
              'refresh' => _refresh(),
              'import' => _import(),
              _ => _export(),
            }),
            itemBuilder: (_) => [
              if (shows.isNotEmpty)
                PopupMenuItem(
                  value: 'refresh',
                  child: Text(l10n.musicPodRefreshAll),
                ),
              PopupMenuItem(value: 'import', child: Text(l10n.musicPodImport)),
              if (shows.isNotEmpty)
                PopupMenuItem(
                  value: 'export',
                  child: Text(l10n.musicPodExport),
                ),
            ],
          ),
        ],
      ),
    );
    if (shows.isEmpty) {
      return Column(
        children: [
          toolbar,
          Expanded(
            child: KEmptyState(
              title: l10n.musicPodEmptyTitle,
              message: l10n.musicPodEmpty,
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          toolbar,
          for (final (show, unplayed) in shows)
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PodcastScreen(showId: show.id),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpacing.s16,
                    vertical: KSpacing.s8,
                  ),
                  child: Row(
                    children: [
                      ShowArt(path: show.artPath, size: 56),
                      const SizedBox(width: KSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              show.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            if (show.author != null)
                              Text(
                                show.author!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            Text(
                              l10n.musicPodUnplayed(unplayed),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

/// Asks for a feed address and subscribes. Pops with the new show.
class SubscribeDialog extends ConsumerStatefulWidget {
  const SubscribeDialog({super.key});

  @override
  ConsumerState<SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends ConsumerState<SubscribeDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  PodcastFailure? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final show = await ref
          .read(podcastServiceProvider)
          .subscribe(_controller.text);
      if (mounted) Navigator.of(context).pop(show);
    } on PodcastException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.reason;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.musicPodAddTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        autocorrect: false,
        onSubmitted: (_) => unawaited(_go()),
        decoration: InputDecoration(
          labelText: l10n.musicPodFeedAddress,
          hintText: l10n.musicPodFeedAddressHint,
          errorText: _error == null ? null : podcastFailureText(l10n, _error!),
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.musicCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_go()),
          child: Text(
            _busy ? l10n.musicPodSubscribing : l10n.musicPodSubscribe,
          ),
        ),
      ],
    );
  }
}

/// What went wrong, in words (docs/06 §8).
String podcastFailureText(AppLocalizations l10n, PodcastFailure f) =>
    switch (f) {
      PodcastFailure.invalidUrl => l10n.musicPodErrInvalid,
      PodcastFailure.unreachable => l10n.musicPodErrUnreachable,
      PodcastFailure.notAFeed => l10n.musicPodErrNotFeed,
      PodcastFailure.tooLarge => l10n.musicPodErrTooLarge,
      PodcastFailure.blocked => l10n.musicPodErrBlocked,
      PodcastFailure.alreadySubscribed => l10n.musicPodErrAlready,
    };
