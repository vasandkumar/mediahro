import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/rules/smart_rule.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/library_screens.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/features/music/ui/now_playing.dart' show askName;
import 'package:mediahro_design/mediahro_design.dart';

/// Music playlists, manual and smart (MUS-001, MUS-008).
class PlaylistsTab extends ConsumerStatefulWidget {
  const PlaylistsTab({super.key});

  @override
  ConsumerState<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<PlaylistsTab> {
  int _reload = 0;

  Future<void> _newManual() async {
    final l10n = AppLocalizations.of(context);
    final name = await askName(
      context,
      title: l10n.musicNewPlaylist,
      label: l10n.musicPlaylistName,
      action: l10n.musicCreate,
    );
    if (name == null) return;
    await ref.read(musicPlaylistsProvider).createManual(name);
    setState(() => _reload++);
  }

  Future<void> _newSmart() async {
    final result = await Navigator.of(context).push<(String, SmartRule)>(
      MaterialPageRoute(builder: (_) => const MusicRuleEditor()),
    );
    if (result == null) return;
    await ref.read(musicPlaylistsProvider).createSmart(result.$1, result.$2);
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final family = Theme.of(context).family;
    return LibraryQuery<List<MusicPlaylist>>(
      queryKey: _reload,
      load: (_) => ref.read(musicPlaylistsProvider).all(),
      builder: (context, lists) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(KSpacing.s8),
            child: Wrap(
              spacing: KSpacing.s8,
              children: [
                ActionChip(
                  avatar: Icon(KIcon.add.resolve(family), size: 18),
                  label: Text(l10n.musicNewPlaylist),
                  onPressed: () => unawaited(_newManual()),
                ),
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(l10n.musicNewSmartPlaylist),
                  onPressed: () => unawaited(_newSmart()),
                ),
              ],
            ),
          ),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(KSpacing.s24),
              child: Text(l10n.musicPlaylistsEmpty),
            ),
          for (final p in lists)
            KRow(
              title: p.name,
              subtitle: p.smart
                  ? l10n.musicArtistAndAlbum(
                      l10n.musicSmartPlaylist,
                      l10n.musicSongCount(p.count),
                    )
                  : l10n.musicSongCount(p.count),
              leading: Icon(p.smart ? Icons.auto_awesome : Icons.queue_music),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlaylistScreen(playlist: p),
                  ),
                );
                if (mounted) setState(() => _reload++);
              },
            ),
        ],
      ),
    );
  }
}

/// One playlist: play/shuffle, songs; reorder and remove (manual), edit
/// the rule (smart), rename and delete.
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({required this.playlist, super.key});

  final MusicPlaylist playlist;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  late MusicPlaylist _p = widget.playlist;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(musicPlaylistsProvider);
    final playingId = ref.watch(
      musicPlayerStateProvider.select((s) => s.value?.current?.itemId),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_p.name),
        actions: [
          if (_p.smart)
            IconButton(
              tooltip: l10n.musicEditRule,
              icon: const Icon(Icons.tune),
              onPressed: () async {
                final r = await Navigator.of(context).push<(String, SmartRule)>(
                  MaterialPageRoute(
                    builder: (_) =>
                        MusicRuleEditor(name: _p.name, initial: _p.rule),
                  ),
                );
                if (r == null) return;
                await repo.updateRule(_p.id, r.$2);
                if (r.$1 != _p.name) await repo.rename(_p.id, r.$1);
                setState(() {
                  _p = MusicPlaylist(
                    id: _p.id,
                    name: r.$1,
                    rule: MusicPlaylists.scoped(r.$2),
                    count: _p.count,
                  );
                  _reload++;
                });
              },
            ),
          PopupMenuButton<String>(
            tooltip: l10n.musicQueueActions,
            onSelected: (v) async {
              final nav = Navigator.of(context);
              switch (v) {
                case 'rename':
                  final name = await askName(
                    context,
                    title: l10n.musicRename,
                    label: l10n.musicPlaylistName,
                    action: l10n.musicSave,
                    initial: _p.name,
                  );
                  if (name == null) return;
                  await repo.rename(_p.id, name);
                  setState(
                    () => _p = MusicPlaylist(
                      id: _p.id,
                      name: name,
                      rule: _p.rule,
                      count: _p.count,
                    ),
                  );
                case 'delete':
                  await repo.delete(_p.id);
                  nav.pop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.musicRename)),
              PopupMenuItem(
                value: 'delete',
                child: Text(l10n.musicDeletePlaylist),
              ),
            ],
          ),
        ],
      ),
      body: LibraryQuery<List<MusicTrack>>(
        queryKey: (_p.id, _reload),
        load: (_) => repo.tracks(_p.id),
        builder: (context, tracks) {
          if (tracks.isEmpty) {
            return KEmptyState(message: l10n.musicPlaylistEmpty);
          }
          final header = PlayShuffleBar(tracks: tracks);
          if (_p.smart) {
            return ListView(
              children: [
                header,
                for (var i = 0; i < tracks.length; i++)
                  TrackRow(
                    track: tracks[i],
                    playing: tracks[i].itemId == playingId,
                    navigation: musicNavigation(context),
                    onTap: () => unawaited(
                      ref
                          .read(musicPlayerProvider)
                          .playTracks(tracks, start: i),
                    ),
                  ),
              ],
            );
          }
          return Column(
            children: [
              header,
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: tracks.length,
                  onReorderItem: (from, to) async {
                    await repo.move(_p.id, from, to);
                    setState(() => _reload++);
                  },
                  itemBuilder: (context, i) => Dismissible(
                    key: ValueKey('pl$i-${tracks[i].itemId}'),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) async {
                      await repo.removeAt(_p.id, i);
                      setState(() => _reload++);
                    },
                    background: ColoredBox(
                      color: Theme.of(context).colorScheme.errorContainer,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TrackRow(
                            track: tracks[i],
                            playing: tracks[i].itemId == playingId,
                            navigation: musicNavigation(context),
                            onTap: () => unawaited(
                              ref
                                  .read(musicPlayerProvider)
                                  .playTracks(tracks, start: i),
                            ),
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Semantics(
                            label: l10n.musicReorderHandle(tracks[i].title),
                            child: const Padding(
                              padding: EdgeInsets.all(KSpacing.s12),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ),
                      ],
                    ),
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

/// One editable condition row.
final class _Cond {
  _Cond(this.field, this.op, String value, [String value2 = ''])
    : value = TextEditingController(text: value),
      value2 = TextEditingController(text: value2);

  RuleField field;
  RuleOp op;
  final TextEditingController value;
  final TextEditingController value2;

  void dispose() {
    value.dispose();
    value2.dispose();
  }
}

/// A group of conditions (all/any); the editor has a top group and any
/// number of sub-groups.
final class _Group {
  _Group({required this.all, List<_Cond>? conds})
    : conds = conds ?? [_Cond(RuleField.genre, RuleOp.equals, '')];

  bool all;
  final List<_Cond> conds;
}

/// Smart playlist rule builder for music (MUS-008): music fields,
/// operators by type, all/any with sub-groups, limit and sort, and a live
/// count of matching songs.
class MusicRuleEditor extends ConsumerStatefulWidget {
  const MusicRuleEditor({this.name, this.initial, super.key});

  final String? name;
  final SmartRule? initial;

  @override
  ConsumerState<MusicRuleEditor> createState() => _MusicRuleEditorState();
}

class _MusicRuleEditorState extends ConsumerState<MusicRuleEditor> {
  late final _name = TextEditingController(text: widget.name ?? '');
  late final List<_Group> _groups;
  final _limit = TextEditingController();
  RuleLimitUnit _unit = RuleLimitUnit.items;
  RuleSort _sort = const RuleSort(RuleField.title);
  int? _matches;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _groups = _fromRule(widget.initial);
    final r = widget.initial;
    if (r != null) {
      if (r.limit != null) _limit.text = '${r.limit}';
      _unit = r.limitUnit;
      _sort = r.sort;
    }
    _schedulePreview();
  }

  List<_Group> _fromRule(SmartRule? r) {
    if (r == null) return [_Group(all: true)];
    final root = r.root;
    if (root is! RuleGroup) return [_Group(all: true)];
    // Length is stored in ms and edited in minutes.
    String show(RuleCondition c, Object? v) =>
        c.field == RuleField.durationMs &&
            v is num &&
            c.op != RuleOp.inLastDays &&
            c.op != RuleOp.notInLastDays
        ? _text(v / 60000)
        : _text(v);
    _Cond cond(RuleCondition c) =>
        _Cond(c.field, c.op, show(c, c.value), show(c, c.value2));
    final top = _Group(
      all: root.matchAll,
      conds: [
        for (final c in root.children)
          if (c is RuleCondition) cond(c),
      ],
    );
    return [
      top,
      for (final g in root.children)
        if (g is RuleGroup)
          _Group(
            all: g.matchAll,
            conds: [
              for (final c in g.children)
                if (c is RuleCondition) cond(c),
            ],
          ),
    ];
  }

  static String _text(Object? v) => switch (v) {
    null => '',
    final List<Object?> l => l.join(', '),
    final num n when n is int || n == n.roundToDouble() => '${n.toInt()}',
    _ => '$v',
  };

  Object? _value(RuleField f, RuleOp op, String text) {
    if (const {
      RuleOp.isSet,
      RuleOp.isNotSet,
      RuleOp.isTrue,
      RuleOp.isFalse,
    }.contains(op)) {
      return null;
    }
    if (op == RuleOp.anyOf) {
      return [
        for (final p in text.split(','))
          if (p.trim().isNotEmpty) p.trim(),
      ];
    }
    if (op == RuleOp.inLastDays || op == RuleOp.notInLastDays) {
      return int.tryParse(text.trim()) ?? 0;
    }
    return switch (f.type) {
      RuleType.number =>
        f == RuleField.durationMs
            // Length is entered in minutes.
            ? ((num.tryParse(text.trim()) ?? 0) * 60000).round()
            : num.tryParse(text.trim()),
      _ => text.trim(),
    };
  }

  SmartRule _rule() {
    RuleCondition c(_Cond x) => RuleCondition(
      x.field,
      x.op,
      _value(x.field, x.op, x.value.text),
      x.op == RuleOp.between ? _value(x.field, x.op, x.value2.text) : null,
    );
    final top = _groups.first;
    return SmartRule(
      root: RuleGroup(
        matchAll: top.all,
        children: [
          for (final x in top.conds) c(x),
          for (final g in _groups.skip(1))
            RuleGroup(
              matchAll: g.all,
              children: [for (final x in g.conds) c(x)],
            ),
        ],
      ),
      limit: int.tryParse(_limit.text.trim()),
      limitUnit: _unit,
      sort: _sort,
    );
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final n = await ref.read(musicPlaylistsProvider).preview(_rule());
        if (mounted) setState(() => _matches = n);
      } on Exception {
        if (mounted) setState(() => _matches = null);
      }
    });
  }

  void _changed(VoidCallback f) {
    setState(f);
    _schedulePreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _limit.dispose();
    for (final g in _groups) {
      for (final c in g.conds) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial == null
              ? l10n.musicNewSmartPlaylist
              : l10n.musicEditRule,
        ),
        actions: [
          TextButton(
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop((_name.text.trim(), _rule())),
            child: Text(l10n.musicSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l10n.musicPlaylistName),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: KSpacing.s8),
          Semantics(
            liveRegion: true,
            child: Text(
              _matches == null ? '' : l10n.musicRuleMatches(_matches!),
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final (gi, g) in _groups.indexed) ...[
            const SizedBox(height: KSpacing.s16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(KSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(l10n.musicRuleMatchAll),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(l10n.musicRuleMatchAny),
                        ),
                      ],
                      selected: {g.all},
                      onSelectionChanged: (v) =>
                          _changed(() => g.all = v.first),
                    ),
                    for (final (ci, c) in g.conds.indexed)
                      _CondRow(
                        cond: c,
                        onChanged: () => _changed(() {}),
                        onRemove: () => _changed(() {
                          g.conds.removeAt(ci).dispose();
                          if (g.conds.isEmpty && gi > 0) _groups.removeAt(gi);
                        }),
                      ),
                    TextButton.icon(
                      onPressed: () => _changed(
                        () => g.conds.add(
                          _Cond(RuleField.artist, RuleOp.contains, ''),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.musicRuleAddCondition),
                    ),
                  ],
                ),
              ),
            ),
          ],
          TextButton.icon(
            onPressed: () => _changed(() => _groups.add(_Group(all: false))),
            icon: const Icon(Icons.account_tree_outlined),
            label: Text(l10n.musicRuleAddGroup),
          ),
          const Divider(height: KSpacing.s32),
          Row(
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _limit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.musicRuleLimit,
                    hintText: l10n.musicRuleNoLimit,
                  ),
                  onChanged: (_) => _changed(() {}),
                ),
              ),
              const SizedBox(width: KSpacing.s12),
              DropdownButton<RuleLimitUnit>(
                value: _unit,
                items: [
                  for (final u in RuleLimitUnit.values)
                    DropdownMenuItem(
                      value: u,
                      child: Text(l10n.musicRuleLimitUnit(u.name)),
                    ),
                ],
                onChanged: (u) => _changed(() => _unit = u!),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.s16),
          Text(l10n.musicRuleSortBy, style: theme.textTheme.titleSmall),
          Row(
            children: [
              Expanded(
                child: DropdownButton<RuleField?>(
                  isExpanded: true,
                  value: _sort.field,
                  items: [
                    DropdownMenuItem(child: Text(l10n.musicRuleRandom)),
                    for (final f in musicRuleFields)
                      DropdownMenuItem(
                        value: f,
                        child: Text(l10n.libraryRuleField(f.name)),
                      ),
                  ],
                  onChanged: (f) => _changed(
                    () => _sort = RuleSort(f, descending: _sort.descending),
                  ),
                ),
              ),
              const SizedBox(width: KSpacing.s8),
              FilterChip(
                label: Text(l10n.musicRuleDescending),
                selected: _sort.descending,
                onSelected: _sort.field == null
                    ? null
                    : (v) => _changed(
                        () => _sort = RuleSort(_sort.field, descending: v),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CondRow extends StatelessWidget {
  const _CondRow({
    required this.cond,
    required this.onChanged,
    required this.onRemove,
  });

  final _Cond cond;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ops = RuleOp.forType(cond.field.type);
    final noValue = const {
      RuleOp.isSet,
      RuleOp.isNotSet,
      RuleOp.isTrue,
      RuleOp.isFalse,
    }.contains(cond.op);
    final days =
        cond.op == RuleOp.inLastDays || cond.op == RuleOp.notInLastDays;
    return Padding(
      padding: const EdgeInsets.only(top: KSpacing.s8),
      child: Wrap(
        spacing: KSpacing.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<RuleField>(
            value: cond.field,
            items: [
              for (final f in musicRuleFields)
                DropdownMenuItem(
                  value: f,
                  child: Text(l10n.libraryRuleField(f.name)),
                ),
            ],
            onChanged: (f) {
              cond.field = f!;
              if (!RuleOp.forType(f.type).contains(cond.op)) {
                cond.op = RuleOp.forType(f.type).first;
              }
              onChanged();
            },
          ),
          DropdownButton<RuleOp>(
            value: ops.contains(cond.op) ? cond.op : ops.first,
            items: [
              for (final o in ops)
                DropdownMenuItem(
                  value: o,
                  child: Text(l10n.libraryRuleOp(o.name)),
                ),
            ],
            onChanged: (o) {
              cond.op = o!;
              onChanged();
            },
          ),
          if (!noValue)
            SizedBox(
              width: 160,
              child: TextField(
                controller: cond.value,
                keyboardType: days || cond.field.type == RuleType.number
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: days ? l10n.musicRuleDays : l10n.musicRuleValue,
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
          if (cond.op == RuleOp.between)
            SizedBox(
              width: 120,
              child: TextField(
                controller: cond.value2,
                decoration: InputDecoration(labelText: l10n.musicRuleValue),
                onChanged: (_) => onChanged(),
              ),
            ),
          IconButton(
            tooltip: l10n.musicRuleRemove,
            icon: Icon(KIcon.close.resolve(Theme.of(context).family)),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
