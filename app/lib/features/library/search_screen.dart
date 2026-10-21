import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:mediahro/core/search/library_search.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Global search (LIB-005): instant prefix search over titles, file names,
/// tags, artists, albums, people and places, with filters.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    this.initialKinds = const {},
    this.initialQuery,
    super.key,
  });

  /// Scope of the current mode by default (docs/06 §2 "scoped by mode").
  final Set<ItemKind> initialKinds;

  /// Text to search for at once (a shared text, a voice search).
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  late Set<ItemKind> _kinds = {...widget.initialKinds};
  final Set<ResolutionClass> _resolutions = {};
  final Set<String> _hdr = {};
  bool _unplayed = false;
  int? _minRating;
  List<ItemRow>? _results;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (_controller.text.isNotEmpty) unawaited(_run());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SearchFilters get _filters => SearchFilters(
    kinds: _kinds,
    resolutions: _resolutions,
    hdrTypes: _hdr,
    unplayedOnly: _unplayed,
    minRating: _minRating,
  );

  Future<void> _run() async {
    final gen = ++_generation;
    final unlocked = ref.read(parentalGateProvider)?.isUnlocked ?? false;
    final results = await ref
        .read(librarySearchProvider)
        .search(
          SearchRequest(
            _controller.text,
            filters: _filters,
            visibility: Visibility(unlocked: unlocked),
          ),
        );
    // Drop stale answers when the user typed on.
    if (mounted && gen == _generation) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.librarySearchHint,
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.librarySearchClear,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      unawaited(_run());
                    },
                  ),
          ),
          onChanged: (_) => unawaited(_run()),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: KTarget.min + KSpacing.s16,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: KSpacing.s12,
                vertical: KSpacing.s8,
              ),
              children: [
                for (final k in const [
                  ItemKind.video,
                  ItemKind.audio,
                  ItemKind.image,
                ])
                  _chip(
                    l10n.libraryKindLabel(k.name),
                    selected: _kinds.contains(k),
                    change: (on) => _kinds = on
                        ? ({..._kinds, k})
                        : ({..._kinds}..remove(k)),
                  ),
                for (final r in const [
                  ResolutionClass.hd,
                  ResolutionClass.fullHd,
                  ResolutionClass.uhd,
                ])
                  _chip(
                    l10n.libraryFilterResolution(r.name),
                    selected: _resolutions.contains(r),
                    change: (on) =>
                        on ? _resolutions.add(r) : _resolutions.remove(r),
                  ),
                _chip(
                  l10n.libraryFilterHdr,
                  selected: _hdr.isNotEmpty,
                  change: (on) {
                    _hdr.clear();
                    if (on) {
                      _hdr.addAll(const [
                        'hdr10',
                        'hdr10plus',
                        'hlg',
                        'dolbyVision',
                      ]);
                    }
                  },
                ),
                _chip(
                  l10n.libraryFilterUnplayed,
                  selected: _unplayed,
                  change: (on) => _unplayed = on,
                ),
                _chip(
                  l10n.libraryFilterRated,
                  selected: _minRating != null,
                  change: (on) => _minRating = on ? 6 : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: results == null
                ? EmptyState(message: l10n.librarySearchPrompt)
                : results.isEmpty
                ? EmptyState(message: l10n.librarySearchNoResults)
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) => ItemTile(
                      item: results[i],
                      onTap: () => ref
                          .read(openItemActionProvider)
                          ?.call(context, results[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label, {
    required bool selected,
    required ValueChanged<bool> change,
  }) => Padding(
    padding: const EdgeInsets.only(right: KSpacing.s8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (on) {
        setState(() => change(on));
        unawaited(_run());
      },
    ),
  );
}
