import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncNotifierProviderFamily;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The folder-or-library choice of one mode, kept in the library database
/// (LIB-004). Without a library (shell-only builds, tests) it stays on the
/// curated library view and the choice lives only for the session.
final AsyncNotifierProviderFamily<ViewModeNotifier, ViewMode, LibraryMode>
viewModeProvider =
    AsyncNotifierProvider.family<ViewModeNotifier, ViewMode, LibraryMode>(
      ViewModeNotifier.new,
    );

class ViewModeNotifier extends AsyncNotifier<ViewMode> {
  ViewModeNotifier(this.mode);

  final LibraryMode mode;

  @override
  Future<ViewMode> build() async {
    try {
      return await ref.read(libraryViewsProvider).viewMode(mode);
    } on Object {
      return ViewMode.library;
    }
  }

  Future<void> set(ViewMode view) async {
    state = AsyncData(view);
    try {
      await ref.read(libraryViewsProvider).setViewMode(mode, view);
    } on Object {
      // The choice still holds for this session.
    }
  }
}

/// App-bar button that switches a mode between its curated library view and
/// its folder view, remembered per mode (LIB-004). It shows the view it
/// would switch to; its label says so.
class ViewModeToggle extends ConsumerWidget {
  const ViewModeToggle({required this.mode, super.key});

  final LibraryMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(viewModeProvider(mode)).value ?? ViewMode.library;
    final folders = current == ViewMode.folders;
    return KIconButton(
      icon: folders ? KIcon.library : KIcon.folder,
      label: folders
          ? l10n.libraryViewShowLibrary
          : l10n.libraryViewShowFolders,
      onPressed: () => unawaited(
        ref
            .read(viewModeProvider(mode).notifier)
            .set(folders ? ViewMode.library : ViewMode.folders),
      ),
    );
  }
}

/// A horizontal home row (LIB-006) for the mode home screens (C1–C3).
class HomeRow extends ConsumerWidget {
  const HomeRow.continueWatching({required this.mode, super.key})
    : _kind = _Row.continueWatching;
  const HomeRow.recentlyAdded({required this.mode, super.key})
    : _kind = _Row.recentlyAdded;
  const HomeRow.recentlyPlayed({required this.mode, super.key})
    : _kind = _Row.recentlyPlayed;
  const HomeRow.unwatched({required this.mode, super.key})
    : _kind = _Row.unwatched;

  final LibraryMode mode;
  final _Row _kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final views = ref.watch(libraryViewsProvider);
    final rows = switch (_kind) {
      _Row.continueWatching =>
        views
            .continueWatching(mode)
            .then((l) => [for (final r in l) (r.item, r.fraction)]),
      _Row.recentlyAdded =>
        views.recentlyAdded(mode).then((l) => [for (final i in l) (i, null)]),
      _Row.recentlyPlayed =>
        views.recentlyPlayed(mode).then((l) => [for (final i in l) (i, null)]),
      _Row.unwatched =>
        views.unwatched(mode).then((l) => [for (final i in l) (i, null)]),
    };
    return FutureBuilder<List<(ItemRow, double?)>>(
      future: rows,
      builder: (context, snap) {
        final list = snap.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpacing.s16,
                KSpacing.s16,
                KSpacing.s16,
                KSpacing.s8,
              ),
              child: Text(
                l10n.libraryHomeRow(_kind.name),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              height: 132,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.s12),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final (item, fraction) = list[i];
                  return SizedBox(
                    width: 180,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => ref
                            .read(openItemActionProvider)
                            ?.call(context, item),
                        child: Padding(
                          padding: const EdgeInsets.all(KSpacing.s8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Icon(kindIcon(item.kind), size: 40),
                                ),
                              ),
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (fraction != null)
                                LinearProgressIndicator(
                                  value: fraction,
                                  semanticsLabel: l10n.libraryResumeProgress(
                                    (fraction * 100).round(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _Row { continueWatching, recentlyAdded, recentlyPlayed, unwatched }

/// Tags and colour label of items, bulk (LIB-009, FILE-003 batch tag edit).
Future<void> showTagEditor(
  BuildContext context,
  WidgetRef ref,
  List<int> itemIds,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _TagEditor(itemIds: itemIds),
);

class _TagEditor extends ConsumerStatefulWidget {
  const _TagEditor({required this.itemIds});

  final List<int> itemIds;

  @override
  ConsumerState<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends ConsumerState<_TagEditor> {
  final _new = TextEditingController();
  Map<String, int> _all = const {};
  Set<String> _onFirst = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = ref.read(tagRepositoryProvider);
    final all = await repo.allTags();
    final first = widget.itemIds.isEmpty
        ? <String>{}
        : (await repo.tagsOf(widget.itemIds.first)).toSet();
    if (mounted) {
      setState(() {
        _all = all;
        _onFirst = first;
      });
    }
  }

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(tagRepositoryProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KSpacing.s16,
        0,
        KSpacing.s16,
        MediaQuery.viewInsetsOf(context).bottom + KSpacing.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.libraryTagsFor(widget.itemIds.length),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Wrap(
            spacing: KSpacing.s8,
            children: [
              for (final t in _all.keys)
                FilterChip(
                  label: Text(t),
                  selected: _onFirst.contains(t),
                  onSelected: (on) async {
                    await (on
                        ? repo.addTag(widget.itemIds, t)
                        : repo.removeTag(widget.itemIds, t));
                    await _load();
                  },
                ),
            ],
          ),
          TextField(
            controller: _new,
            decoration: InputDecoration(labelText: l10n.libraryNewTag),
            onSubmitted: (v) async {
              if (v.trim().isEmpty) return;
              await repo.addTag(widget.itemIds, v);
              _new.clear();
              await _load();
            },
          ),
          const SizedBox(height: KSpacing.s16),
          Text(
            l10n.libraryLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Wrap(
            spacing: KSpacing.s8,
            children: [
              for (final c in LabelColor.values)
                ActionChip(
                  avatar: CircleAvatar(backgroundColor: _color(c)),
                  label: Text(l10n.libraryLabelColor(c.name)),
                  onPressed: () => repo.setLabel(widget.itemIds, c),
                ),
              ActionChip(
                label: Text(l10n.libraryLabelNone),
                onPressed: () => repo.setLabel(widget.itemIds, null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _color(LabelColor c) => switch (c) {
    LabelColor.red => const Color(0xFFE5484D),
    LabelColor.orange => const Color(0xFFF76B15),
    LabelColor.yellow => const Color(0xFFFFC53D),
    LabelColor.green => const Color(0xFF30A46C),
    LabelColor.blue => const Color(0xFF0090FF),
    LabelColor.purple => const Color(0xFF8E4EC6),
    LabelColor.grey => const Color(0xFF8B8D98),
  };
}
