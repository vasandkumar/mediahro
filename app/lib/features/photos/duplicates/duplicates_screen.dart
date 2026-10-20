import 'dart:async';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/duplicates.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/photos/duplicates/photo_duplicates.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/trash/trash_screen.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The duplicate finder for photos (IMG-013): exact copies and photos that
/// look the same, each group reviewed side by side. Nothing is ever deleted
/// without the user choosing it, and what is deleted goes to Recently
/// deleted.
class PhotoDuplicatesScreen extends ConsumerStatefulWidget {
  const PhotoDuplicatesScreen({super.key});

  @override
  ConsumerState<PhotoDuplicatesScreen> createState() =>
      _PhotoDuplicatesScreenState();
}

class _PhotoDuplicatesScreenState extends ConsumerState<PhotoDuplicatesScreen> {
  late final ThumbnailController _thumbs;
  bool _exact = true;
  bool _similar = true;
  bool _running = false;
  bool _stop = false;
  int _done = 0;
  int _total = 0;
  DuplicateScan? _result;

  @override
  void initState() {
    super.initState();
    _thumbs = ThumbnailController(ref.read(thumbnailSourceProvider(256)));
  }

  @override
  void dispose() {
    _stop = true;
    _thumbs.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _stop = false;
      _done = 0;
      _total = 0;
      _result = null;
    });
    try {
      final r = await ref
          .read(photoDuplicateScannerProvider)
          .scan(
            exact: _exact,
            similar: _similar,
            onProgress: (d, t) {
              if (mounted) {
                setState(() {
                  _done = d;
                  _total = t;
                });
              }
            },
            cancelled: () => _stop,
          );
      if (mounted) setState(() => _result = r);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  PhotoEntry _entry(ItemRow item, Map<int, PhotoEntry> byId) =>
      byId[item.id] ?? photoEntryOfItem(item);

  Future<void> _open(DuplicateGroup g, Map<int, PhotoEntry> byId) async {
    final removed = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        builder: (_) => DuplicateReviewScreen(
          group: g,
          photos: [for (final i in g.items) _entry(i, byId)],
          keepId: g.suggestedKeep.id,
        ),
      ),
    );
    if (removed == null || removed.isEmpty || !mounted) return;
    setState(() {
      final r = _result;
      if (r == null) return;
      final groups = <DuplicateGroup>[];
      for (final x in r.groups) {
        final left = [
          for (final i in x.items)
            if (!removed.contains(i.id)) i,
        ];
        if (left.length > 1) {
          groups.add(DuplicateGroup(x.kind, left, similarity: x.similarity));
        }
      }
      _result = DuplicateScan(groups, stopped: r.stopped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final byId = {
      for (final e
          in ref.watch(photoEntriesProvider).value ?? const <PhotoEntry>[])
        e.id: e,
    };
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.photosDuplicates)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(l10n.photosDuplicatesExact),
                      selected: _exact,
                      onSelected: _running
                          ? null
                          : (v) => setState(() => _exact = v),
                    ),
                    FilterChip(
                      label: Text(l10n.photosDuplicatesSimilar),
                      selected: _similar,
                      onSelected: _running
                          ? null
                          : (v) => setState(() => _similar = v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_running)
                  Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _total > 0
                              ? l10n.photosDuplicatesScanning(_done, _total)
                              : l10n.photosDuplicatesComparing,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _total > 0 ? _done / _total : null,
                        ),
                        TextButton(
                          onPressed: () => setState(() => _stop = true),
                          child: Text(l10n.photosBatchStop),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton(
                    onPressed: (_exact || _similar)
                        ? () => unawaited(_run())
                        : null,
                    child: Text(l10n.photosDuplicatesFind),
                  ),
              ],
            ),
          ),
          Expanded(
            child: r == null
                ? (_running
                      ? const SizedBox.shrink()
                      : KEmptyState(message: l10n.photosDuplicatesIntro))
                : r.groups.isEmpty
                ? KEmptyState(
                    title: l10n.photosDuplicatesNone,
                    message: l10n.photosDuplicatesNoneMessage,
                  )
                : ListView(
                    children: [
                      if (r.stopped)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(l10n.photosBatchStopped),
                        ),
                      for (final g in r.groups)
                        _GroupTile(
                          group: g,
                          entries: [for (final i in g.items) _entry(i, byId)],
                          thumbs: _thumbs,
                          onTap: () => unawaited(_open(g, byId)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.entries,
    required this.thumbs,
    required this.onTap,
  });

  final DuplicateGroup group;
  final List<PhotoEntry> entries;
  final ThumbnailController thumbs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = group.kind == DuplicateKind.exact
        ? l10n.photosDuplicatesKindExact
        : l10n.photosDuplicatesKindSimilar;
    return ListTile(
      onTap: onTap,
      title: Text(l10n.photosDuplicatesGroup(entries.length, kind)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < entries.length && i < 6; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SizedBox.square(
                    dimension: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(KRadius.sm),
                      child: PhotoThumbnail(
                        entry: entries[i],
                        index: i,
                        controller: thumbs,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// A group side by side: pan and zoom together, then choose which to keep.
/// Popping returns the ids that were deleted.
class DuplicateReviewScreen extends ConsumerStatefulWidget {
  const DuplicateReviewScreen({
    required this.group,
    required this.photos,
    required this.keepId,
    super.key,
  });

  final DuplicateGroup group;
  final List<PhotoEntry> photos;

  /// The one kept to start with (the largest, then the biggest file).
  final int keepId;

  @override
  ConsumerState<DuplicateReviewScreen> createState() =>
      _DuplicateReviewScreenState();
}

class _DuplicateReviewScreenState extends ConsumerState<DuplicateReviewScreen> {
  static const _shown = 4;
  final TransformationController _zoom = TransformationController();
  late final Set<int> _keep = {widget.keepId};
  late final Map<int, ViewerImage?> _images = {};
  late final Set<int> _failed = {};
  bool _disposed = false;

  /// The photos in the comparison: the kept one first, then the others.
  late final List<PhotoEntry> _compared = [
    ...widget.photos.where((p) => p.id == widget.keepId),
    ...widget.photos.where((p) => p.id != widget.keepId),
  ].take(_shown).toList();

  @override
  void initState() {
    super.initState();
    final load = ref.read(viewerImageLoaderProvider);
    for (final p in _compared) {
      unawaited(_load(load, p));
    }
  }

  Future<void> _load(ViewerImageLoader load, PhotoEntry p) async {
    try {
      final img = await load(p);
      if (_disposed) {
        img.dispose();
        return;
      }
      setState(() => _images[p.id] = img);
    } on Object {
      if (!_disposed) setState(() => _failed.add(p.id));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in _images.values) {
      i?.dispose();
    }
    _zoom.dispose();
    super.dispose();
  }

  List<PhotoEntry> get _toDelete => [
    for (final p in widget.photos)
      if (!_keep.contains(p.id)) p,
  ];

  Future<void> _delete() async {
    final gone = _toDelete;
    if (gone.isEmpty || _keep.isEmpty) return;
    final done = await deletePhotosFlow(context, ref, gone);
    if (done && mounted) {
      Navigator.of(context).pop({for (final p in gone) p.id});
    }
  }

  Widget _panel(PhotoEntry p) {
    if (_failed.contains(p.id)) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54),
      );
    }
    final img = _images[p.id];
    if (img == null) return const Center(child: CircularProgressIndicator());
    return RawImage(image: img.base, fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final scheme = Theme.of(context).colorScheme;
    final gone = _toDelete;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.photosDuplicatesReview),
        actions: [
          IconButton(
            tooltip: l10n.photosCompareResetZoom,
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: () => _zoom.value = Matrix4.identity(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _compared.length >= 2
                ? KCompareView(
                    controller: _zoom,
                    children: [for (final p in _compared) _panel(p)],
                  )
                : const SizedBox.shrink(),
          ),
          Material(
            color: scheme.surfaceContainerHigh,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 152,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      itemCount: widget.photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final p = widget.photos[i];
                        final kept = _keep.contains(p.id);
                        final dims = p.width != null && p.height != null
                            ? '${p.width} × ${p.height}'
                            : null;
                        return Container(
                          width: 210,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: kept
                                  ? Colors.green
                                  : scheme.outlineVariant,
                              width: kept ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(KRadius.sm),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                [
                                  ?dims,
                                  formatBytes(p.size, locale: locale),
                                ].join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                DateFormat.yMMMd(locale).format(p.date),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              SwitchListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(l10n.photosDuplicatesKeep),
                                value: kept,
                                onChanged: (v) => setState(
                                  () =>
                                      v ? _keep.add(p.id) : _keep.remove(p.id),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: gone.isEmpty || _keep.isEmpty
                            ? null
                            : () => unawaited(_delete()),
                        label: Text(
                          _keep.isEmpty
                              ? l10n.photosDuplicatesKeepOne
                              : l10n.photosDuplicatesDelete(gone.length),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
