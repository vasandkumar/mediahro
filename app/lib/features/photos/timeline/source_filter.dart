import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';

/// Which source the timeline shows (IMG-016): null for all of them. Kept for
/// the session only.
class PhotoSourceFilter extends Notifier<int?> {
  @override
  int? build() => null;

  int? get source => state;

  set source(int? sourceId) => state = sourceId;
}

final NotifierProvider<PhotoSourceFilter, int?> photoSourceFilterProvider =
    NotifierProvider<PhotoSourceFilter, int?>(PhotoSourceFilter.new);

/// A source that has photos in the timeline.
typedef TimelineSource = ({
  int id,
  String name,
  int count,
  SourceKind? kind,
  SourceHealth health,
});

/// The sources of [entries], most photos first then by name. A source the
/// library no longer lists is named by [unnamed].
List<TimelineSource> timelineSources(
  List<PhotoEntry> entries,
  List<SourceSummary> summaries,
  String Function(int id) unnamed,
) {
  final counts = <int, int>{};
  for (final e in entries) {
    counts.update(e.sourceId, (n) => n + 1, ifAbsent: () => 1);
  }
  final byId = {for (final s in summaries) s.source.id: s};
  final out = [
    for (final c in counts.entries)
      (
        id: c.key,
        name: byId[c.key]?.source.name ?? unnamed(c.key),
        count: c.value,
        kind: byId[c.key]?.source.kind,
        health: byId[c.key]?.health ?? SourceHealth.unknown,
      ),
  ];
  return out..sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0
        ? byCount
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// [entries] of the source [selected], or all when it is null or no longer
/// has photos.
List<PhotoEntry> filterBySource(
  List<PhotoEntry> entries,
  int? selected,
  List<TimelineSource> sources,
) {
  if (selected == null || !sources.any((s) => s.id == selected)) {
    return entries;
  }
  return [
    for (final e in entries)
      if (e.sourceId == selected) e,
  ];
}

IconData _iconOf(TimelineSource s) {
  if (s.health == SourceHealth.unreachable) return Icons.cloud_off_outlined;
  return switch (s.kind) {
    SourceKind.local || SourceKind.archive => Icons.folder_outlined,
    SourceKind.smb || SourceKind.nfs => Icons.dns_outlined,
    SourceKind.webdav ||
    SourceKind.ftp ||
    SourceKind.sftp ||
    SourceKind.cloud ||
    SourceKind.server => Icons.cloud_outlined,
    _ => Icons.storage_outlined,
  };
}

/// A row of chips to show the photos of all sources or of one (IMG-016). A
/// source that could not be reached on its last scan says so; its photos stay
/// listed from what the library already knows.
class SourceFilterBar extends StatelessWidget {
  const SourceFilterBar({
    required this.sources,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<TimelineSource> sources;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.photosSourceFilter,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(l10n.photosSourceAll),
                selected: selected == null,
                onSelected: (_) => onSelect(null),
              ),
            ),
            for (final s in sources)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Semantics(
                  label: s.health == SourceHealth.unreachable
                      ? l10n.photosSourceUnreachable(s.name)
                      : null,
                  child: ChoiceChip(
                    avatar: Icon(_iconOf(s), size: 18),
                    label: Text('${s.name} (${s.count})'),
                    selected: selected == s.id,
                    onSelected: (_) => onSelect(s.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
