import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Manual and smart playlists (LIB-007).
class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  Future<void> _create({required bool smart}) async {
    final repo = ref.read(playlistRepositoryProvider);
    final nav = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    if (smart) {
      final rule = await nav.push<(String, SmartRule)>(
        MaterialPageRoute(builder: (_) => const SmartRuleEditor()),
      );
      if (rule != null) await repo.createSmart(rule.$1, rule.$2);
    } else {
      final c = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l10n.libraryNewPlaylist),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.libraryName),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(d).pop(c.text),
              child: Text(l10n.libraryOk),
            ),
          ],
        ),
      );
      if (name != null && name.trim().isNotEmpty) {
        await repo.createManual(name.trim());
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(playlistRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryPlaylists),
        actions: [
          IconButton(
            tooltip: l10n.libraryNewSmartPlaylist,
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => _create(smart: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.libraryNewPlaylist,
        onPressed: () => _create(smart: false),
        child: const Icon(Icons.playlist_add),
      ),
      body: FutureBuilder<List<PlaylistRow>>(
        future: repo.all(),
        builder: (context, snap) {
          final rows = snap.data;
          if (rows == null) return const SkeletonList();
          if (rows.isEmpty) return EmptyState(message: l10n.libraryNoPlaylists);
          return ListView(
            children: [
              for (final p in rows)
                ListTile(
                  leading: Icon(
                    p.rule == null
                        ? Icons.queue_music_outlined
                        : Icons.auto_awesome_outlined,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    p.rule == null
                        ? l10n.libraryManualPlaylist
                        : l10n.librarySmartPlaylist,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlaylistScreen(playlist: p),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({required this.playlist, super.key});

  final PlaylistRow playlist;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  List<PlaylistTrack>? _tracks;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final t = await ref
        .read(playlistRepositoryProvider)
        .tracks(widget.playlist.id);
    if (mounted) setState(() => _tracks = t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(playlistRepositoryProvider);
    final tracks = _tracks;
    final manual = widget.playlist.rule == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            tooltip: l10n.libraryDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final nav = Navigator.of(context);
              await repo.delete(widget.playlist.id);
              nav.pop();
            },
          ),
        ],
      ),
      body: tracks == null
          ? const SkeletonList()
          : tracks.isEmpty
          ? EmptyState(message: l10n.libraryPlaylistEmpty)
          : manual
          ? ReorderableListView.builder(
              itemCount: tracks.length,
              onReorderItem: (from, to) async {
                await repo.move(widget.playlist.id, from, to);
                await _load();
              },
              itemBuilder: (context, i) => ListTile(
                key: ValueKey('t$i-${tracks[i].displayTitle}'),
                title: Text(tracks[i].displayTitle),
                trailing: IconButton(
                  tooltip: l10n.libraryRemoveFromPlaylist,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () async {
                    await repo.removeAt(widget.playlist.id, i);
                    await _load();
                  },
                ),
              ),
            )
          : ListView(
              children: [
                for (final t in tracks)
                  if (t.item != null)
                    ItemTile(
                      item: t.item!,
                      onTap: () => ref
                          .read(openItemActionProvider)
                          ?.call(context, t.item!),
                    ),
              ],
            ),
    );
  }
}

/// Rule builder (LIB-007): any indexed field, AND/OR, limit, sort.
class SmartRuleEditor extends StatefulWidget {
  const SmartRuleEditor({super.key});

  @override
  State<SmartRuleEditor> createState() => _SmartRuleEditorState();
}

class _SmartRuleEditorState extends State<SmartRuleEditor> {
  final _name = TextEditingController();
  bool _all = true;
  final _conditions = <(RuleField, RuleOp, TextEditingController)>[
    (RuleField.genre, RuleOp.equals, TextEditingController()),
  ];
  final _limit = TextEditingController();
  RuleLimitUnit _unit = RuleLimitUnit.items;
  RuleSort _sort = const RuleSort(RuleField.title);

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    for (final c in _conditions) {
      c.$3.dispose();
    }
    super.dispose();
  }

  Object? _value(RuleField f, String text) => switch (f.type) {
    RuleType.number => num.tryParse(text),
    RuleType.date => int.tryParse(text) ?? text,
    _ => text,
  };

  SmartRule _rule() => SmartRule(
    root: RuleGroup(
      matchAll: _all,
      children: [
        for (final (f, op, c) in _conditions)
          if (op == RuleOp.between && c.text.contains('-'))
            RuleCondition(
              f,
              op,
              _value(f, c.text.split('-').first.trim()),
              _value(f, c.text.split('-').last.trim()),
            )
          else
            RuleCondition(
              f,
              op,
              op == RuleOp.isSet ||
                      op == RuleOp.isNotSet ||
                      op == RuleOp.isTrue ||
                      op == RuleOp.isFalse
                  ? null
                  : _value(f, c.text),
            ),
      ],
    ),
    limit: int.tryParse(_limit.text),
    limitUnit: _unit,
    sort: _sort,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryNewSmartPlaylist),
        actions: [
          TextButton(
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop((_name.text.trim(), _rule())),
            child: Text(l10n.sourcesSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l10n.libraryName),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: KSpacing.s16),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(l10n.libraryMatchAll)),
              ButtonSegment(value: false, label: Text(l10n.libraryMatchAny)),
            ],
            selected: {_all},
            onSelectionChanged: (v) => setState(() => _all = v.first),
          ),
          for (var i = 0; i < _conditions.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: KSpacing.s12),
              child: Wrap(
                spacing: KSpacing.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<RuleField>(
                    value: _conditions[i].$1,
                    items: [
                      for (final f in RuleField.values)
                        DropdownMenuItem(
                          value: f,
                          child: Text(l10n.libraryRuleField(f.name)),
                        ),
                    ],
                    onChanged: (f) => setState(() {
                      final ops = RuleOp.forType(f!.type);
                      _conditions[i] = (f, ops.first, _conditions[i].$3);
                    }),
                  ),
                  DropdownButton<RuleOp>(
                    value: _conditions[i].$2,
                    items: [
                      for (final o in RuleOp.forType(_conditions[i].$1.type))
                        DropdownMenuItem(
                          value: o,
                          child: Text(l10n.libraryRuleOp(o.name)),
                        ),
                    ],
                    onChanged: (o) => setState(
                      () => _conditions[i] = (
                        _conditions[i].$1,
                        o!,
                        _conditions[i].$3,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _conditions[i].$3,
                      decoration: InputDecoration(
                        labelText: l10n.libraryRuleValue,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.libraryRemoveCondition,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _conditions.length == 1
                        ? null
                        : () => setState(() => _conditions.removeAt(i)),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => setState(
              () => _conditions.add((
                RuleField.title,
                RuleOp.contains,
                TextEditingController(),
              )),
            ),
            icon: const Icon(Icons.add),
            label: Text(l10n.libraryAddCondition),
          ),
          const Divider(),
          Wrap(
            spacing: KSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _limit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.libraryLimit),
                ),
              ),
              DropdownButton<RuleLimitUnit>(
                value: _unit,
                items: [
                  for (final u in RuleLimitUnit.values)
                    DropdownMenuItem(
                      value: u,
                      child: Text(l10n.libraryLimitUnit(u.name)),
                    ),
                ],
                onChanged: (u) => setState(() => _unit = u!),
              ),
              DropdownButton<RuleField?>(
                value: _sort.field,
                items: [
                  DropdownMenuItem(child: Text(l10n.librarySortRandom)),
                  for (final f in const [
                    RuleField.title,
                    RuleField.dateAdded,
                    RuleField.lastPlayed,
                    RuleField.playCount,
                    RuleField.rating,
                    RuleField.year,
                  ])
                    DropdownMenuItem(
                      value: f,
                      child: Text(l10n.libraryRuleField(f.name)),
                    ),
                ],
                onChanged: (f) => setState(
                  () => _sort = RuleSort(f, descending: _sort.descending),
                ),
              ),
              FilterChip(
                label: Text(l10n.libraryDescending),
                selected: _sort.descending,
                onSelected: (d) => setState(
                  () => _sort = RuleSort(_sort.field, descending: d),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
