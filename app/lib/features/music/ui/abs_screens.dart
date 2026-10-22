import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/music/abs/abs_account.dart';
import 'package:mediahro/features/music/abs/abs_player.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro/features/music/ui/spoken_player_screen.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

/// Plays [item] of [account] and opens the player; a server that cannot be
/// reached is said so.
Future<void> playAbs(
  BuildContext context,
  WidgetRef ref,
  AbsAccount account,
  ServerItem item, {
  List<ServerItem> queue = const [],
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(absPlayerProvider).play(account, item, queue: queue);
  } on ServerException {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.musicAbsUnreachable(account.name))),
    );
    return;
  }
  if (context.mounted) openNowPlaying(context);
}

/// The cover of [item] from this device, fetched through the gateway.
class AbsCover extends ConsumerWidget {
  const AbsCover({required this.item, required this.size, super.key});

  final ServerItem item;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(_coverProvider(item)).value;
    return ShowArt(path: path, size: size);
  }
}

final FutureProviderFamily<String?, ServerItem> _coverProvider =
    FutureProvider.family<String?, ServerItem>(
      (ref, item) => ref.watch(absServiceProvider).artPath(item),
      retry: _noRetry,
    );

/// The Audiobookshelf tab (POD-003): continue listening, then the libraries
/// of each connected server. The tab is shown only when a server is
/// connected.
class AbsTab extends ConsumerWidget {
  const AbsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(audiobookshelfAccountsProvider);
    if (accounts.isEmpty) {
      return KEmptyState(title: l10n.musicTabAbs, message: l10n.musicAbsNone);
    }
    final entries = ref.watch(absContinueProvider).value ?? const [];
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(absContinueProvider),
      child: ListView(
        children: [
          if (entries.isNotEmpty) ...[
            _Header(l10n.musicAbsContinue),
            for (final e in entries)
              AbsItemTile(
                account: e.account,
                item: e.item,
                showServer: accounts.length > 1,
                onTap: () =>
                    unawaited(playAbs(context, ref, e.account, e.item)),
              ),
          ],
          for (final a in accounts) ...[
            _Header(a.name),
            _Libraries(account: a),
          ],
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpacing.s16,
      KSpacing.s16,
      KSpacing.s16,
      KSpacing.s4,
    ),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// A server that cannot be reached is said so with a button to try again,
/// not retried in the background.
Duration? _noRetry(int retryCount, Object error) => null;

final FutureProviderFamily<List<ServerItem>, AbsAccount> _librariesProvider =
    FutureProvider.family<List<ServerItem>, AbsAccount>(
      (ref, a) => ref.watch(absServiceProvider).libraries(a),
      retry: _noRetry,
    );

class _Libraries extends ConsumerWidget {
  const _Libraries({required this.account});

  final AbsAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(_librariesProvider(account));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(KSpacing.s16),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => ListTile(
        title: Text(l10n.musicAbsUnreachable(account.name)),
        trailing: TextButton(
          onPressed: () => ref.invalidate(_librariesProvider(account)),
          child: Text(l10n.musicPodRetry),
        ),
      ),
      data: (libs) => Column(
        children: [
          for (final l in libs)
            ListTile(
              leading: Icon(
                l.kind == ServerItemKind.podcast ||
                        l.extra['mediaType'] == 'podcast'
                    ? Icons.podcasts
                    : Icons.menu_book_outlined,
              ),
              title: Text(l.title),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AbsBrowseScreen(account: account, parent: l),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One row: cover, title, author, and how far the listener is.
class AbsItemTile extends ConsumerWidget {
  const AbsItemTile({
    required this.account,
    required this.item,
    required this.onTap,
    this.showServer = false,
    super.key,
  });

  final AbsAccount account;
  final ServerItem item;
  final VoidCallback onTap;
  final bool showServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final d = item.duration;
    final p = item.playedPosition;
    final fraction = d == null || d.inMilliseconds == 0 || p == null
        ? null
        : (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
    final playing = ref.watch(
      absPlayerStateProvider.select((s) => s.value?.item?.id),
    );
    final subtitle = item.author ?? (showServer ? account.name : null);
    return Semantics(
      selected: playing == item.id,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KSpacing.s16,
              vertical: KSpacing.s8,
            ),
            child: Row(
              children: [
                AbsCover(item: item, size: 56),
                const SizedBox(width: KSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: playing == item.id
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (fraction != null && !item.played)
                        Padding(
                          padding: const EdgeInsets.only(top: KSpacing.s4),
                          child: ExcludeSemantics(
                            child: LinearProgressIndicator(value: fraction),
                          ),
                        ),
                      if (item.played)
                        Text(
                          l10n.musicBookFinished,
                          style: theme.textTheme.bodySmall,
                        )
                      else if (d != null)
                        Text(
                          formatDuration(d),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (item.isPodcast || item.kind == ServerItemKind.folder)
                  const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The items inside a library or a podcast, a page at a time, with search
/// across the server.
class AbsBrowseScreen extends ConsumerStatefulWidget {
  const AbsBrowseScreen({
    required this.account,
    required this.parent,
    super.key,
  });

  final AbsAccount account;
  final ServerItem parent;

  @override
  ConsumerState<AbsBrowseScreen> createState() => _AbsBrowseScreenState();
}

class _AbsBrowseScreenState extends ConsumerState<AbsBrowseScreen> {
  final _items = <ServerItem>[];
  String? _cursor;
  bool _loading = false;
  bool _failed = false;
  bool _done = false;
  String? _query;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_more());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final service = ref.read(absServiceProvider);
    try {
      final page = await service.browse(
        widget.account,
        widget.parent.id,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
        _loading = false;
      });
    } on ServerException {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _query = null);
      return;
    }
    setState(() {
      _query = query;
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(absServiceProvider)
          .search(widget.account, query);
      if (!mounted || _query != query) return;
      setState(() {
        _results = page.items;
        _loading = false;
      });
    } on ServerException {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  List<ServerItem> _results = const [];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shown = _query == null ? _items : _results;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parent.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.s16,
              0,
              KSpacing.s16,
              KSpacing.s8,
            ),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => unawaited(_search(q)),
              decoration: InputDecoration(
                hintText: l10n.musicAbsSearch,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: _failed && shown.isEmpty
          ? KEmptyState(
              message: l10n.musicAbsUnreachable(widget.account.name),
              actions: [
                FilledButton(
                  onPressed: () =>
                      unawaited(_query == null ? _more() : _search(_query!)),
                  child: Text(l10n.musicPodRetry),
                ),
              ],
            )
          : shown.isEmpty && !_loading
          ? KEmptyState(message: l10n.musicAbsNoResults)
          : ListView.builder(
              itemCount: shown.length + 1,
              itemBuilder: (context, i) {
                if (i == shown.length) {
                  if (_query == null && !_done) {
                    unawaited(Future(_more));
                    return const Padding(
                      padding: EdgeInsets.all(KSpacing.s16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return const SizedBox(height: 96);
                }
                final item = shown[i];
                return AbsItemTile(
                  account: widget.account,
                  item: item,
                  onTap: () => _open(context, item, shown),
                );
              },
            ),
    );
  }

  void _open(BuildContext context, ServerItem item, List<ServerItem> list) {
    if (item.isPodcast || item.kind == ServerItemKind.folder) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AbsBrowseScreen(account: widget.account, parent: item),
        ),
      );
    } else if (item.kind == ServerItemKind.podcastEpisode) {
      unawaited(
        playAbs(
          context,
          ref,
          widget.account,
          item,
          queue: _query == null ? _items : const [],
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AbsItemScreen(account: widget.account, item: item),
        ),
      );
    }
  }
}

/// A book: cover, who wrote and read it, how long it is, and play, offline
/// copy and finished marks.
class AbsItemScreen extends ConsumerStatefulWidget {
  const AbsItemScreen({required this.account, required this.item, super.key});

  final AbsAccount account;
  final ServerItem item;

  @override
  ConsumerState<AbsItemScreen> createState() => _AbsItemScreenState();
}

class _AbsItemScreenState extends ConsumerState<AbsItemScreen> {
  EpisodeDownload? _download;
  late bool _played = widget.item.played;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final d = await ref
        .read(absServiceProvider)
        .downloadStatus(widget.account, widget.item);
    if (!mounted) return;
    setState(() => _download = d);
    final running =
        d != null &&
        !d.done &&
        d.state.name != 'failed' &&
        d.state.name != 'paused';
    _poll?.cancel();
    if (running) {
      _poll = Timer(const Duration(seconds: 2), () => unawaited(_refresh()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final item = widget.item;
    final service = ref.read(absServiceProvider);
    final p = item.playedPosition;
    final resuming = !_played && p != null && p > Duration.zero;
    final d = _download;
    return Scaffold(
      appBar: AppBar(title: Text(item.title, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          Center(child: AbsCover(item: item, size: 200)),
          const SizedBox(height: KSpacing.s16),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          if (item.author != null)
            Text(
              l10n.musicAbsBy(item.author!),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          if (item.narrator != null)
            Text(
              l10n.musicAbsNarratedBy(item.narrator!),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          if (item.series != null)
            Text(
              item.series!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          if (item.duration != null)
            Text(
              formatDuration(item.duration!),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: KSpacing.s16),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(
              resuming
                  ? l10n.musicAbsResumeAt(formatDuration(p))
                  : l10n.musicPlay,
            ),
            onPressed: () =>
                unawaited(playAbs(context, ref, widget.account, item)),
          ),
          const SizedBox(height: KSpacing.s8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: KSpacing.s8,
            children: [
              if (d == null || d.state.name == 'failed')
                OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(l10n.musicPodDownload),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    try {
                      await service.download(widget.account, item);
                    } on ServerException {
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.musicAbsUnreachable(widget.account.name),
                          ),
                        ),
                      );
                    }
                    await _refresh();
                  },
                )
              else
                OutlinedButton.icon(
                  icon: Icon(d.done ? Icons.download_done : Icons.downloading),
                  label: Text(
                    d.done
                        ? l10n.musicPodRemoveDownload
                        : l10n.musicPodDownloadQueued,
                  ),
                  onPressed: () async {
                    await service.removeDownload(widget.account, item);
                    await _refresh();
                  },
                ),
              OutlinedButton.icon(
                icon: Icon(_played ? Icons.undo : Icons.check_circle_outline),
                label: Text(
                  _played
                      ? l10n.musicAbsMarkNotFinished
                      : l10n.musicAbsMarkFinished,
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  try {
                    await service.setPlayed(
                      widget.account,
                      item,
                      played: !_played,
                    );
                    if (mounted) setState(() => _played = !_played);
                  } on ServerException {
                    messenger?.showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n.musicAbsUnreachable(widget.account.name),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          if (item.overview != null) ...[
            const SizedBox(height: KSpacing.s16),
            SelectableText(item.overview!),
          ],
        ],
      ),
    );
  }
}

/// The player while an Audiobookshelf item is in play (POD-003).
class AbsPlayerScreen extends ConsumerWidget {
  const AbsPlayerScreen({required this.state, super.key});

  final AbsPlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.read(absPlayerProvider);
    final item = state.item!;
    return SpokenPlayerScreen(
      title: l10n.musicTabAbs,
      view: SpokenView(
        title: item.title,
        subtitle: item.author ?? state.account!.name,
        artPath: state.artPath,
        position: state.position,
        duration: state.duration,
        speed: state.speed,
        skipSilence: state.skipSilence,
        playing: state.playing,
        offline: state.offline,
        chapters: [
          for (final c in state.chapters) SpokenChapter(c.start, c.title ?? ''),
        ],
      ),
      controls: SpokenControls(
        toggle: () => unawaited(player.togglePlayPause()),
        seek: (p) => unawaited(player.seek(p)),
        setSpeed: (s) => unawaited(player.setSpeed(s)),
        setSkipSilence: ({required enabled}) =>
            unawaited(player.setSkipSilence(enabled: enabled)),
        speed: absPlayerStateProvider.select((s) => s.value?.speed ?? 1),
        speedNote: (l10n) => l10n.musicAbsSpeedRemembered,
        markPlayed: () => unawaited(player.markFinished()),
        showNotes: item.overview == null
            ? null
            : () => unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (sheet) => FractionallySizedBox(
                    heightFactor: 0.7,
                    child: ListView(
                      padding: const EdgeInsets.all(KSpacing.s16),
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(sheet).textTheme.titleLarge,
                        ),
                        const SizedBox(height: KSpacing.s12),
                        SelectableText(item.overview!),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
