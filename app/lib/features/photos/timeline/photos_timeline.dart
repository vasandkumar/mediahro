import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The photo timeline (IMG-003): dated sections, square or proportional
/// rows, pinch to change density, a year/month scrubber, and thumbnails
/// scheduled by distance from the viewport.
class PhotoTimeline extends ConsumerStatefulWidget {
  const PhotoTimeline({super.key});

  @override
  ConsumerState<PhotoTimeline> createState() => _PhotoTimelineState();
}

class _PhotoTimelineState extends ConsumerState<PhotoTimeline> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _fraction = ValueNotifier(0);
  ThumbnailController? _thumbs;
  int _thumbEdge = 256;

  int _columns = 4;
  bool _justified = false;
  double _pinch = 1;
  int _pinchBase = 4;

  TimelineLayout? _layout;
  Object? _layoutKey;
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
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
  ) {
    final key = (
      identityHashCode(entries),
      width.round(),
      _columns,
      _justified,
      headerHeight.round(),
    );
    if (_layout != null && _layoutKey == key) return _layout!;
    _layoutKey = key;
    return _layout = TimelineLayout.build(
      entries,
      width: width,
      columns: _columns,
      justified: _justified,
      headerHeight: headerHeight,
      grouping: _columns >= 6 ? TimelineGrouping.month : TimelineGrouping.day,
    );
  }

  void _setColumns(int n) {
    final capped = n.clamp(1, 6);
    if (capped == _columns) return;
    // Keep the photo at the top of the screen where it is.
    final layout = _layout;
    int? anchor;
    if (layout != null && _scroll.hasClients) {
      anchor =
          layout.entriesBetween(_scroll.offset, _scroll.offset + 1)?.first ??
          layout.entriesBetween(_scroll.offset, _scroll.offset + 200)?.first;
    }
    setState(() => _columns = capped);
    if (anchor != null) {
      final a = anchor;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final l = _layout;
        if (l == null || !_scroll.hasClients) return;
        _scroll.jumpTo(
          l.rectOf(a).top.clamp(0.0, _scroll.position.maxScrollExtent),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final entries = ref.watch(photoEntriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appNavPhotos),
        actions: [
          IconButton(
            tooltip: _justified
                ? l10n.photosLayoutSquare
                : l10n.photosLayoutAspect,
            icon: Icon(
              _justified ? Icons.grid_view_outlined : Icons.view_quilt_outlined,
            ),
            onPressed: () => setState(() => _justified = !_justified),
          ),
          PopupMenuButton<int>(
            tooltip: l10n.photosDensityLabel,
            icon: const Icon(Icons.density_medium_outlined),
            initialValue: _columns,
            onSelected: _setColumns,
            itemBuilder: (_) => [
              for (var n = 1; n <= 6; n++)
                CheckedPopupMenuItem(
                  value: n,
                  checked: n == _columns,
                  child: Text(NumberFormat.decimalPattern(locale).format(n)),
                ),
            ],
          ),
        ],
      ),
      body: entries.when(
        data: (list) =>
            list.isEmpty ? _empty(context) : _timeline(context, list),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => KErrorState(
          message: l10n.photosLoadFailedTitle,
          action: KButton(
            label: l10n.photosRetry,
            onPressed: () => ref.invalidate(photoEntriesProvider),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KEmptyState(
      title: l10n.photosEmptyTitle,
      message: l10n.photosEmptyMessage,
      actions: [
        KButton(
          label: l10n.photosAddPhotos,
          variant: KButtonVariant.primary,
          onPressed: () => context.go(AppRoutes.addFolder),
        ),
      ],
    );
  }

  Widget _timeline(BuildContext context, List<PhotoEntry> entries) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.maxHeight;
        // The scrubber sits over the trailing edge; tiles use the rest.
        final width = constraints.maxWidth;
        final double headerHeight = math.max(48, scaler.scale(24) + 24);
        final layout = _layoutFor(entries, width, headerHeight);
        final tileWidth = (width - 2 * (_columns - 1)) / _columns;
        final edge = tileWidth * dpr > 300 ? 512 : 256;
        final thumbs = _controllerFor(edge);
        WidgetsBinding.instance.addPostFrameCallback((_) => _reportViewport());
        final now = DateTime.now();
        String headerLabel(TimelineSection s) {
          final today = DateTime(now.year, now.month, now.day);
          if (_columns < 6) {
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
          onScaleStart: (d) {
            _pinch = 1;
            _pinchBase = _columns;
          },
          onScaleUpdate: (d) {
            if (d.pointerCount < 2) return;
            _pinch = d.scale;
            // Spreading fingers → bigger photos → fewer columns.
            final n = (_pinchBase / _pinch).round();
            _setColumns(n);
          },
          child: Stack(
            children: [
              Semantics(
                label: l10n.photosTimelineLabel,
                container: true,
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: layout.rows.length,
                  scrollCacheExtent: ScrollCacheExtent.pixels(
                    constraints.maxHeight * 2,
                  ),
                  itemExtentBuilder: (i, _) =>
                      layout.rows[i].height +
                      (layout.rows[i] is TileRow ? layout.gap : 0),
                  itemBuilder: (context, i) {
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
                                      cacheWidth: (row.widths[k] * dpr).round(),
                                      locale: locale,
                                      onOpen: () => openPhotoViewer(
                                        context,
                                        entries,
                                        row.firstEntry + k,
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

  /// One mark per month (a year when sections are months of many years).
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
    required this.cacheWidth,
    required this.locale,
    required this.onOpen,
    super.key,
  });

  final PhotoEntry entry;
  final int index;
  final ThumbnailController controller;
  final int cacheWidth;
  final String locale;
  final VoidCallback onOpen;

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
    return RepaintBoundary(
      child: KGridTile(
        semanticLabel: l10n.photosTileLabel(
          entry.isVideo ? 'video' : 'photo',
          DateFormat.yMMMEd(locale).add_jm().format(entry.date),
        ),
        badges: badges,
        onTap: onOpen,
        artwork: PhotoThumbnail(
          entry: entry,
          index: index,
          controller: controller,
          cacheWidth: cacheWidth,
        ),
      ),
    );
  }
}
