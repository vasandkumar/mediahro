import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/duplicates.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/library/parental_gate.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/library/playlists_screen.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Entry to library tools shared by the three modes: playlists, queues,
/// collections, duplicates, statistics, parental controls.
class LibraryHubScreen extends StatelessWidget {
  const LibraryHubScreen({this.mode = LibraryMode.video, super.key});

  final LibraryMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void go(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTools)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.queue_music_outlined),
            title: Text(l10n.libraryPlaylists),
            onTap: () => go(const PlaylistsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.low_priority),
            title: Text(l10n.libraryQueues),
            onTap: () => go(const QueuesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: Text(l10n.libraryCollections),
            onTap: () => go(CollectionsScreen(mode: mode)),
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: Text(l10n.libraryDuplicates),
            onTap: () => go(const DuplicatesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: Text(l10n.libraryStatistics),
            onTap: () => go(const StatisticsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.libraryParental),
            onTap: () => go(const ParentalScreen()),
          ),
        ],
      ),
    );
  }
}

/// Named audio queues and the video queue (LIB-008).
class QueuesScreen extends ConsumerStatefulWidget {
  const QueuesScreen({super.key});

  @override
  ConsumerState<QueuesScreen> createState() => _QueuesScreenState();
}

class _QueuesScreenState extends ConsumerState<QueuesScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(queueRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryQueues)),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.libraryNewQueue,
        onPressed: () async {
          final c = TextEditingController();
          final name = await showDialog<String>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text(l10n.libraryNewQueue),
              content: TextField(controller: c, autofocus: true),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(d).pop(c.text),
                  child: Text(l10n.libraryOk),
                ),
              ],
            ),
          );
          if (name != null && name.trim().isNotEmpty) {
            await repo.createAudioQueue(name.trim());
          }
        },
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<QueueRow>>(
        stream: repo.watchAudioQueues(),
        builder: (context, snap) {
          final queues = snap.data;
          if (queues == null) return const SkeletonList();
          if (queues.isEmpty) return EmptyState(message: l10n.libraryNoQueues);
          return RadioGroup<int>(
            groupValue: queues.where((x) => x.active).firstOrNull?.id,
            onChanged: (id) => repo.activate(id!),
            child: ListView(
              children: [
                for (final q in queues)
                  RadioListTile<int>(
                    value: q.id,
                    title: Text(q.name),
                    subtitle: Text(
                      l10n.libraryQueueRepeat(
                        RepeatMode.values.byName(q.repeat).name,
                      ),
                    ),
                    secondary: IconButton(
                      tooltip: l10n.libraryDelete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => repo.delete(q.id),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Library-mode groupings (LIB-012).
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({required this.mode, super.key});

  final LibraryMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final kinds = switch (mode) {
      LibraryMode.video => const [
        CollectionKind.series,
        CollectionKind.movieCollections,
        CollectionKind.years,
      ],
      LibraryMode.music => const [
        CollectionKind.albums,
        CollectionKind.artists,
        CollectionKind.genres,
        CollectionKind.years,
        CollectionKind.composers,
      ],
      LibraryMode.photos => const [
        CollectionKind.photoAlbums,
        CollectionKind.people,
        CollectionKind.places,
      ],
    };
    return DefaultTabController(
      length: kinds.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.libraryCollections),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final k in kinds)
                Tab(text: l10n.libraryCollectionKind(k.name)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final k in kinds)
              FutureBuilder<List<Collection>>(
                future: ref.read(libraryViewsProvider).collections(k),
                builder: (context, snap) {
                  final rows = snap.data;
                  if (rows == null) return const SkeletonList();
                  if (rows.isEmpty) {
                    return EmptyState(message: l10n.libraryCollectionsEmpty);
                  }
                  return ListView(
                    children: [
                      for (final c in rows)
                        ListTile(
                          title: Text(c.title),
                          subtitle: Text(l10n.sourcesItemCount(c.itemCount)),
                          trailing: c.year == null
                              ? null
                              : Text(
                                  formatCount(
                                    c.year!,
                                    locale: Localizations.localeOf(context)
                                        .toLanguageTag(),
                                    grouping: false,
                                  ),
                                ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Duplicate review (LIB-014): the user chooses; nothing is deleted
/// automatically. Deletion goes through the file browser's trash flow.
class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  Future<List<DuplicateGroup>>? _groups;
  final Set<DuplicateKind> _kinds = {...DuplicateKind.values};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryDuplicates)),
      body: Column(
        children: [
          Wrap(
            spacing: KSpacing.s8,
            children: [
              for (final k in DuplicateKind.values)
                FilterChip(
                  label: Text(l10n.libraryDuplicateKind(k.name)),
                  selected: _kinds.contains(k),
                  onSelected: (on) =>
                      setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                ),
              FilledButton.tonal(
                onPressed: () => setState(
                  () =>
                      _groups = ref.read(duplicateFinderProvider).find(_kinds),
                ),
                child: Text(l10n.libraryFindDuplicates),
              ),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<DuplicateGroup>>(
              future: _groups,
              builder: (context, snap) {
                if (_groups == null) {
                  return EmptyState(message: l10n.libraryDuplicatesIntro);
                }
                final groups = snap.data;
                if (groups == null) return const SkeletonList();
                if (groups.isEmpty) {
                  return EmptyState(message: l10n.libraryNoDuplicates);
                }
                return ListView(
                  children: [
                    for (final g in groups)
                      ExpansionTile(
                        title: Text(
                          l10n.libraryDuplicateGroup(
                            g.items.length,
                            l10n.libraryDuplicateKind(g.kind.name),
                          ),
                        ),
                        children: [
                          for (final i in g.items)
                            ItemTile(
                              item: i,
                              trailing: i.id == g.suggestedKeep.id
                                  ? Chip(
                                      label: Text(l10n.libraryKeepSuggestion),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Play counts, time played, top items, storage by type and source (LIB-015).
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryStatistics)),
      body: FutureBuilder<LibraryStats>(
        future: ref.read(libraryViewsProvider).stats(),
        builder: (context, snap) {
          final s = snap.data;
          if (s == null) return const SkeletonList();
          return ListView(
            children: [
              ListTile(
                title: Text(l10n.libraryStatPlays),
                trailing: Text(
                  formatCount(
                    s.playCount,
                    locale: Localizations.localeOf(context).toLanguageTag(),
                  ),
                ),
              ),
              ListTile(
                title: Text(l10n.libraryStatTime),
                trailing: Text(formatDuration(s.timePlayed)),
              ),
              ListTile(
                title: Text(
                  l10n.libraryStatTop,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final (item, n) in s.topItems)
                ItemTile(
                  item: item,
                  trailing: Text(
                    formatCount(
                      n,
                      locale: Localizations.localeOf(context).toLanguageTag(),
                    ),
                  ),
                ),
              ListTile(
                title: Text(
                  l10n.libraryStatStorage,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final e in s.bytesByKind.entries)
                ListTile(
                  title: Text(l10n.libraryKindLabel(e.key.name)),
                  subtitle: Text(
                    l10n.sourcesItemCount(s.countByKind[e.key] ?? 0),
                  ),
                  trailing: Text(formatBytes(e.value, locale: locale)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Parental PIN and locked sources (LIB-013).
class ParentalScreen extends ConsumerStatefulWidget {
  const ParentalScreen({super.key});

  @override
  ConsumerState<ParentalScreen> createState() => _ParentalScreenState();
}

class _ParentalScreenState extends ConsumerState<ParentalScreen> {
  final _pin = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gate = ref.watch(parentalGateProvider);
    if (gate == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.libraryParental)),
        body: EmptyState(message: l10n.libraryParentalUnavailable),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryParental)),
      body: FutureBuilder<bool>(
        future: gate.hasPin,
        builder: (context, snap) {
          final hasPin = snap.data ?? false;
          return ListView(
            padding: const EdgeInsets.all(KSpacing.s16),
            children: [
              Text(l10n.libraryParentalIntro),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: InputDecoration(labelText: l10n.libraryPin),
              ),
              Wrap(
                spacing: KSpacing.s8,
                children: [
                  if (!hasPin || gate.isUnlocked)
                    FilledButton(
                      onPressed: () async {
                        try {
                          await gate.setPin(_pin.text);
                          setState(() => _message = l10n.libraryPinSet);
                        } on ParentalGateException catch (e) {
                          setState(
                            () => _message =
                                e.reason == ParentalGateRefusal.invalidPin
                                ? l10n.libraryPinInvalid
                                : l10n.libraryUnlockFirst,
                          );
                        }
                      },
                      child: Text(
                        hasPin ? l10n.libraryChangePin : l10n.librarySetPin,
                      ),
                    ),
                  if (hasPin && !gate.isUnlocked)
                    FilledButton(
                      onPressed: () async {
                        final r = await gate.unlock(
                          pin: _pin.text.isEmpty ? null : _pin.text,
                          reason: l10n.libraryUnlockReason,
                        );
                        setState(
                          () => _message = l10n.libraryUnlockResult(r.name),
                        );
                      },
                      child: Text(l10n.libraryUnlock),
                    ),
                  if (gate.isUnlocked)
                    OutlinedButton(
                      onPressed: () => setState(() {
                        gate.lock();
                        _message = null;
                      }),
                      child: Text(l10n.libraryLock),
                    ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: KSpacing.s8),
                  child: Text(_message!),
                ),
              const Divider(),
              if (hasPin)
                FutureBuilder<List<SourceRow>>(
                  future: () {
                    final db = ref.read(libraryDatabaseProvider);
                    return db.select(db.sources).get();
                  }(),
                  builder: (context, s) => Column(
                    children: [
                      for (final src in s.data ?? const <SourceRow>[])
                        SwitchListTile(
                          title: Text(src.name),
                          subtitle: Text(l10n.libraryLockSourceHint),
                          value: src.locked,
                          onChanged: (v) async {
                            try {
                              await gate.setSourceLocked(src.id, locked: v);
                            } on ParentalGateException {
                              setState(
                                () => _message = l10n.libraryUnlockFirst,
                              );
                            }
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
