import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/organise/photo_selection.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_layout.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// A scrolling grid of photos in dated sections (IMG-003, IMG-005): square
/// or proportional rows, pinch to change density, a year/month scrubber,
/// thumbnails scheduled by distance from the viewport, and multi-selection
/// by long press and drag. Used by the timeline, albums and folders.
class PhotoGrid extends ConsumerStatefulWidget {
  const PhotoGrid({
    required this.entries,
    required this.selection,
    this.bottomPadding = 0,
    super.key,
  });

  /// Newest first.
  final List<PhotoEntry> entries;
  final PhotoSelection selection;

  /// Room under the last row (a bar that floats over the grid).
  final double bottomPadding;

  @override
  ConsumerState<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends ConsumerState<PhotoGrid> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _fraction = ValueNotifier(0);
  ThumbnailController? _thumbs;
  int _thumbEdge = 256;

  int _pinchBase = 4;

  TimelineLayout? _layout;
  Object? _layoutKey;
  double _viewport = 0;
  List<int> _ids = const [];
  List<PhotoEntry>? _idsFor;

  // Drag selection.
  Offset? _pointer;
  Timer? _edgeScroll;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _edgeScroll?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _fraction.dispose();
    _thumbs?.dispose();
    super.dispose();
  }

  ThumbnailController _controllerFor(int edge) {
    if (_thumbs != null && _thumbEdge == edge) return _thumbs!;
    _thumbs?.dispose();
    _thumbEdge = edge;
    return _thumbs = ThumbnailController(
      ref.read(thumbnailSourceProvider(edge)),
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _fraction.value = max <= 0 ? 0 : (_scroll.offset / max).clamp(0.0, 1.0);
    _reportViewport();
  }

  void _reportViewport() {
    final layout = _layout;
    final thumbs = _thumbs;
    if (layout == null || thumbs == null || !_scroll.hasClients) return;
    final off = _scroll.offset;
    final r = layout.entriesBetween(off, off + _viewport);
    if (r == null) return;
    thumbs.viewport(
      r.first,
      r.last,
      screenItems: math.max(8, r.last - r.first + 1),
    );
  }

  TimelineLayout _layoutFor(
    List<PhotoEntry> entries,
    double width,
    double headerHeight,
    PhotoLayoutSettings s,
  ) {
    final key = (
      identityHashCode(entries),
      width.round(),
      s.columns,
      s.justified,
      headerHeight.round(),
    );
    if (_layout != null && _layoutKey == key) return _layout!;
    _layoutKey = key;
    return _layout = TimelineLayout.build(
      entries,
      width: width,
      columns: s.columns,
      justified: s.justified,
      headerHeight: headerHeight,
      grouping: s.columns >= 6 ? TimelineGrouping.month : TimelineGrouping.day,
    );
  }

  /// Keeps the photo at the top of the screen where it is when the density
  /// changes.
  void _keepAnchor() {
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    final anchor =
        layout.entriesBetween(_scroll.offset, _scroll.offset + 1)?.first ??
        layout.entriesBetween(_scroll.offset, _scroll.offset + 200)?.first;
    if (anchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final l = _layout;
      if (l == null || !_scroll.hasClients) return;
      _scroll.jumpTo(
        l.rectOf(anchor).top.clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }

  // ---- drag selection ---------------------------------------------------

  int? _entryAtPointer() {
    final p = _pointer;
    final layout = _layout;
    if (p == null || layout == null || !_scroll.hasClients) return null;
    return layout.entryAt(Offset(p.dx, p.dy + _scroll.offset));
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!widget.selection.dragging) return;
    _pointer = e.localPosition;
    _edgeScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final p = _pointer;
      if (p == null || !_scroll.hasClients) return;
      var d = 0.0;
      if (p.dy < 72) d = -(72 - p.dy) / 4;
      if (p.dy > _viewport - 72) d = (p.dy - (_viewport - 72)) / 4;
      if (d != 0) {
        _scroll.jumpTo(
          (_scroll.offset + d).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      }
      _dragSelect();
    });
    _dragSelect();
  }

  void _dragSelect() {
    final i = _entryAtPointer();
    if (i != null) widget.selection.dragTo(i, _ids);
  }

  void _endDrag([PointerEvent? _]) {
    _edgeScroll?.cancel();
    _edgeScroll = null;
    _pointer = null;
    widget.selection.endDrag();
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (!identical(_idsFor, entries)) {
      _idsFor = entries;
      _ids = [for (final e in entries) e.id];
    }
    ref.listen(photoLayoutProvider, (prev, next) {
      if (prev != null && prev.columns != next.columns) _keepAnchor();
    });
    final settings = ref.watch(photoLayoutProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.maxHeight;
        final width = constraints.maxWidth;
        final double headerHeight = math.max(48, scaler.scale(24) + 24);
        final layout = _layoutFor(entries, width, headerHeight, settings);
        final tileWidth =
            (width - 2 * (settings.columns - 1)) / settings.columns;
        final edge = tileWidth * dpr > 300 ? 512 : 256;
        final thumbs = _controllerFor(edge);
        WidgetsBinding.instance.addPostFrameCallback((_) => _reportViewport());
        final now = DateTime.now();
        String headerLabel(TimelineSection s) {
          final today = DateTime(now.year, now.month, now.day);
          if (settings.columns < 6) {
            if (s.date == today) return l10n.photosToday;
            if (s.date == today.subtract(const Duration(days: 1))) {
              return l10n.photosYesterday;
            }
            return DateFormat.yMMMEd(locale).format(s.date);
          }
          return DateFormat.yMMMM(locale).format(s.date);
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: (d) =>
              _pinchBase = ref.read(photoLayoutProvider).columns,
          onScaleUpdate: (d) {
            if (d.pointerCount < 2) return;
            // Spreading fingers → bigger photos → fewer columns.
            ref
                .read(photoLayoutProvider.notifier)
                .setColumns((_pinchBase / d.scale).round());
          },
          child: Stack(
            children: [
              Semantics(
                label: l10n.photosTimelineLabel,
                container: true,
                child: Listener(
                  onPointerMove: _onPointerMove,
                  onPointerUp: _endDrag,
                  onPointerCancel: _endDrag,
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: layout.rows.length + 1,
                    scrollCacheExtent: ScrollCacheExtent.pixels(
                      constraints.maxHeight * 2,
                    ),
                    itemExtentBuilder: (i, _) => i == layout.rows.length
                        ? widget.bottomPadding
                        : layout.rows[i].height +
                              (layout.rows[i] is TileRow ? layout.gap : 0),
                    itemBuilder: (context, i) {
                      if (i == layout.rows.length) return const SizedBox();
                      final row = layout.rows[i];
                      switch (row) {
                        case HeaderRow():
                          return _Header(
                            label: headerLabel(layout.sections[row.section]),
                          );
                        case TileRow():
                          return Align(
                            alignment: AlignmentDirectional.topStart,
                            child: SizedBox(
                              height: row.height,
                              child: Row(
                                children: [
                                  for (var k = 0; k < row.count; k++) ...[
                                    if (k > 0) SizedBox(width: layout.gap),
                                    SizedBox(
                                      width: row.widths[k],
                                      height: row.height,
                                      child: _Tile(
                                        key: ValueKey(
                                          entries[row.firstEntry + k].id,
                                        ),
                                        entry: entries[row.firstEntry + k],
                                        index: row.firstEntry + k,
                                        controller: thumbs,
                                        selection: widget.selection,
                                        cacheWidth: (row.widths[k] * dpr)
                                            .round(),
                                        locale: locale,
                                        onOpen: () {
                                          final s = widget.selection;
                                          final id =
                                              entries[row.firstEntry + k].id;
                                          if (s.active) {
                                            s.toggle(id);
                                          } else {
                                            unawaited(
                                              openPhotoViewer(
                                                context,
                                                entries,
                                                row.firstEntry + k,
                                              ),
                                            );
                                          }
                                        },
                                        onSelect: () =>
                                            widget.selection.beginDrag(
                                              row.firstEntry + k,
                                              _ids,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                      }
                    },
                  ),
                ),
              ),
              PositionedDirectional(
                top: 0,
                bottom: 0,
                end: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _fraction,
                  builder: (context, f, _) => KTimelineScrubber(
                    label: l10n.photosScrubberLabel,
                    fraction: f,
                    marks: _marks(layout, locale),
                    onChanged: (v) {
                      if (!_scroll.hasClients) return;
                      _scroll.jumpTo(v * _scroll.position.maxScrollExtent);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// One mark per month.
  List<KTimelineMark> _marks(TimelineLayout layout, String locale) {
    final max = math.max(1, layout.totalHeight - _viewport);
    final out = <KTimelineMark>[];
    int? lastKey;
    for (var s = 0; s < layout.sections.length; s++) {
      final d = layout.sections[s].date;
      final key = d.year * 100 + d.month;
      if (key == lastKey) continue;
      lastKey = key;
      out.add(
        KTimelineMark(
          label: DateFormat.yMMM(locale).format(d),
          fraction: (layout.offsetOfSection(s) / max).clamp(0.0, 1.0),
        ),
      );
    }
    return out;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: KSpacing.s12,
      end: KSpacing.s48,
      top: KSpacing.s12,
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        header: true,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.entry,
    required this.index,
    required this.controller,
    required this.selection,
    required this.cacheWidth,
    required this.locale,
    required this.onOpen,
    required this.onSelect,
    super.key,
  });

  final PhotoEntry entry;
  final int index;
  final ThumbnailController controller;
  final PhotoSelection selection;
  final int cacheWidth;
  final String locale;
  final VoidCallback onOpen;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final badges = [
      if (entry.isRaw) l10n.photosBadgeRaw,
      if (entry.livePhoto) l10n.photosBadgeLive,
      if (entry.motionPhoto) l10n.photosBadgeMotion,
      if (entry.hdr) l10n.photosBadgeHdr,
      if (entry.isVideo && entry.durationMs != null)
        formatMediaDuration(Duration(milliseconds: entry.durationMs!)),
    ];
    final when = DateFormat.yMMMEd(locale).add_jm().format(entry.date);
    final kind = entry.isVideo ? 'video' : 'photo';
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: selection,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            KGridTile(
              semanticLabel: entry.favourite
                  ? l10n.photosTileLabelFavourite(kind, when)
                  : l10n.photosTileLabel(kind, when),
              badges: badges,
              selected: selection.contains(entry.id),
              selectionMode: selection.active,
              onTap: onOpen,
              onLongPress: onSelect,
              artwork: PhotoThumbnail(
                entry: entry,
                index: index,
                controller: controller,
                cacheWidth: cacheWidth,
              ),
            ),
            if (entry.favourite)
              const PositionedDirectional(
                top: KSpacing.s4,
                end: KSpacing.s4,
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.favorite,
                    size: 18,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
