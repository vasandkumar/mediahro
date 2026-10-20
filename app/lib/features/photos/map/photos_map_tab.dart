import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/clustering.dart';
import 'package:mediahro/features/photos/map/map_providers.dart';
import 'package:mediahro/features/photos/map/map_surface.dart';
import 'package:mediahro/features/photos/map/tiles_prompt.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart';
import 'package:mediahro/features/photos/organise/photo_collection_view.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_viewer.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The Map tab (IMG-007): every geotagged photo on a map, grouped into
/// markers that split as you zoom in.
class PhotosMapTab extends ConsumerStatefulWidget {
  const PhotosMapTab({super.key});

  @override
  ConsumerState<PhotosMapTab> createState() => _PhotosMapTabState();
}

class _PhotosMapTabState extends ConsumerState<PhotosMapTab> {
  late final ThumbnailController _thumbs;
  MapController? _controller;

  @override
  void initState() {
    super.initState();
    _thumbs = ThumbnailController(ref.read(thumbnailSourceProvider(256)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    _thumbs.dispose();
    super.dispose();
  }

  GeoBounds _boundsOf(List<GeoPhoto> photos) =>
      GeoBounds.around([for (final p in photos) (lat: p.lat, lon: p.lon)]);

  void _openCluster(
    PhotoCluster cluster,
    MapCamera camera,
    Map<int, PhotoEntry> byId,
    List<PhotoEntry> geoEntries,
  ) {
    if (cluster.count == 1) {
      final at = geoEntries.indexWhere((e) => e.id == cluster.cover.id);
      if (at >= 0) unawaited(openPhotoViewer(context, geoEntries, at));
      return;
    }
    if (!cluster.coincident && camera.zoom < 17.5) {
      unawaited(
        _controller?.animateTo(
              MapCamera(
                center: (lat: cluster.lat, lon: cluster.lon),
                zoom: zoomToSplit(cluster, camera),
                size: camera.size,
              ).constrained(),
            ) ??
            Future.value(),
      );
      return;
    }
    final ids = {for (final p in cluster.photos) p.id};
    final here = [
      for (final e in geoEntries)
        if (ids.contains(e.id)) e,
    ];
    unawaited(_showHere(here));
  }

  Future<void> _showHere(List<PhotoEntry> entries) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      builder: (context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.photosMapHereTitle(entries.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: PhotoCollectionView(
              entries: entries,
              emptyMessage: l10n.photosMapNoPhotosMessage,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final geo = ref.watch(geoPhotosProvider);
    final entries = ref.watch(photoEntriesProvider).value;
    final tilesOn = ref.watch(mapTilesEnabledProvider).value ?? false;
    final photos = geo.value;
    if (photos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (photos.isEmpty) {
      return KEmptyState(
        title: l10n.photosMapNoPhotosTitle,
        message: l10n.photosMapNoPhotosMessage,
      );
    }
    final controller = _controller ??= MapController(
      initialBounds: _boundsOf(photos),
    );
    final byId = {for (final e in entries ?? const <PhotoEntry>[]) e.id: e};
    final geoIds = {for (final p in photos) p.id};
    final geoEntries = [
      for (final e in entries ?? const <PhotoEntry>[])
        if (geoIds.contains(e.id)) e,
    ];
    final tiles = ref.watch(mapTileSourceProvider);

    return Stack(
      children: [
        Positioned.fill(
          child: MapSurface(
            controller: controller,
            tiles: tiles,
            overlay: (context, camera) {
              final clusters = clusterPhotos(photos, camera);
              return [
                for (var i = 0; i < clusters.length; i++)
                  _marker(clusters[i], i, camera, byId, geoEntries, l10n),
              ];
            },
          ),
        ),
        if (!tilesOn)
          const PositionedDirectional(
            top: 8,
            start: 8,
            end: 8,
            child: MapTilesOffCard(),
          ),
        if (tilesOn)
          PositionedDirectional(
            bottom: 4,
            start: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  l10n.photosMapAttribution,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
        PositionedDirectional(
          bottom: 16,
          end: 8,
          child: MapControls(
            controller: controller,
            onShowAll: () => unawaited(controller.fit(_boundsOf(photos))),
          ),
        ),
      ],
    );
  }

  Widget _marker(
    PhotoCluster cluster,
    int index,
    MapCamera camera,
    Map<int, PhotoEntry> byId,
    List<PhotoEntry> geoEntries,
    AppLocalizations l10n,
  ) {
    const size = ClusterMarker.size;
    final at = camera.toScreen(cluster.lat, cluster.lon);
    return Positioned(
      key: ValueKey(cluster.cover.id),
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      width: size,
      height: size,
      child: ClusterMarker(
        entry: byId[cluster.cover.id],
        count: cluster.count,
        index: index,
        controller: _thumbs,
        label: l10n.photosMapMarkerLabel(cluster.count),
        onTap: () => _openCluster(cluster, camera, byId, geoEntries),
      ),
    );
  }
}

/// A round photo with a count: one cluster of the map.
class ClusterMarker extends StatelessWidget {
  const ClusterMarker({
    required this.entry,
    required this.count,
    required this.index,
    required this.controller,
    required this.label,
    required this.onTap,
    super.key,
  });

  static const double size = 56;

  final PhotoEntry? entry;
  final int count;
  final int index;
  final ThumbnailController controller;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHigh,
                  border: Border.all(color: scheme.surface, width: 2.5),
                  boxShadow: const [
                    BoxShadow(blurRadius: 4, color: Color(0x55000000)),
                  ],
                ),
                child: ClipOval(
                  child: e == null
                      ? Icon(Icons.photo, color: scheme.onSurfaceVariant)
                      : PhotoThumbnail(
                          entry: e,
                          index: index,
                          controller: controller,
                          cacheWidth: 112,
                        ),
                ),
              ),
            ),
            if (count > 1)
              PositionedDirectional(
                top: -4,
                end: -6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    child: Text(
                      count > 999 ? '999+' : '$count',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onPrimary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Zoom in, zoom out and "show all" buttons, 48 dp targets.
class MapControls extends StatelessWidget {
  const MapControls({required this.controller, this.onShowAll, super.key});

  final MapController controller;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(IconData icon, String tip, VoidCallback onPressed) =>
        IconButton.filledTonal(
          tooltip: tip,
          icon: Icon(icon),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: onPressed,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (onShowAll != null)
          button(Icons.zoom_out_map, l10n.photosMapShowAll, onShowAll!),
        button(
          Icons.add,
          l10n.photosMapZoomIn,
          () => unawaited(controller.zoomBy(1)),
        ),
        button(
          Icons.remove,
          l10n.photosMapZoomOut,
          () => unawaited(controller.zoomBy(-1)),
        ),
      ],
    );
  }
}
