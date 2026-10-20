import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/map_providers.dart';
import 'package:mediahro/features/photos/map/map_surface.dart';
import 'package:mediahro/features/photos/map/photos_map_tab.dart'
    show MapControls;
import 'package:mediahro/features/photos/map/tiles_prompt.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart';

/// A position the user chose.
typedef PickedLocation = ({double lat, double lon});

/// Opens the map full screen and returns where the pin was left, or null
/// when the user backed out (IMG-007 set location).
Future<PickedLocation?> pickLocation(
  BuildContext context, {
  GeoPoint? initial,
}) => Navigator.of(context).push<PickedLocation>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => LocationPickerScreen(initial: initial),
  ),
);

/// Pan the map under a fixed pin, or search a city, then confirm. The pin is
/// at the centre of the screen, so the choice works with a finger, a mouse
/// or the arrow keys alike.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({this.initial, super.key});

  final GeoPoint? initial;

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  late final MapController _controller = MapController(
    initialCenter: widget.initial,
    initialZoom: widget.initial == null ? 2 : 14,
  );
  final TextEditingController _query = TextEditingController();
  List<GazetteerPlace> _matches = const [];

  @override
  void dispose() {
    _controller.dispose();
    _query.dispose();
    super.dispose();
  }

  void _search(String text) {
    final g = ref.read(gazetteerProvider).value;
    setState(() => _matches = g?.search(text) ?? const []);
  }

  void _goTo(GazetteerPlace p) {
    final cam = _controller.camera;
    if (cam == null) return;
    setState(() => _matches = const []);
    _query.clear();
    FocusScope.of(context).unfocus();
    unawaited(
      _controller.animateTo(
        MapCamera(
          center: (lat: p.latitude, lon: p.longitude),
          zoom: 11,
          size: cam.size,
        ).constrained(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tilesOn = ref.watch(mapTilesEnabledProvider).value ?? false;
    final hasSearch = ref.watch(gazetteerProvider).value != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.photosPickLocationTitle),
        leading: IconButton(
          tooltip: l10n.photosPickLocationClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapSurface(
              controller: _controller,
              tiles: ref.watch(mapTileSourceProvider),
              autofocus: true,
              onTap: (camera, at) {
                // Bring the tapped spot under the pin.
                final mid = Offset(
                  camera.size.width / 2,
                  camera.size.height / 2,
                );
                unawaited(_controller.animateTo(camera.panned(mid - at)));
              },
              overlay: (context, camera) => [
                // The pin's tip is the chosen position (the screen centre).
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -24),
                      child: Icon(
                        Icons.location_on,
                        size: 48,
                        color: scheme.error,
                        shadows: const [
                          Shadow(blurRadius: 4, color: Color(0x66000000)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 8,
            start: 8,
            end: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!tilesOn) const MapTilesOffCard(),
                if (hasSearch) ...[
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(28),
                    child: TextField(
                      controller: _query,
                      onChanged: _search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: l10n.photosPickLocationSearch,
                        prefixIcon: const Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  if (_query.text.trim().isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(top: 4),
                      child: _matches.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(l10n.photosPickLocationNoMatch),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final p in _matches)
                                  ListTile(
                                    title: Text(p.name),
                                    subtitle: Text(p.country),
                                    onTap: () => _goTo(p),
                                  ),
                              ],
                            ),
                    ),
                ],
              ],
            ),
          ),
          PositionedDirectional(
            bottom: 112,
            end: 8,
            child: MapControls(controller: _controller),
          ),
          PositionedDirectional(
            bottom: 0,
            start: 0,
            end: 0,
            child: Material(
              elevation: 6,
              color: scheme.surfaceContainerHigh,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      final c = _controller.camera?.center;
                      final text = c == null
                          ? ''
                          : '${c.lat.toStringAsFixed(5)}, '
                                '${c.lon.toStringAsFixed(5)}';
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.photosPickLocationHint,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              text,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: c == null
                                  ? null
                                  : () => Navigator.pop<PickedLocation>(
                                      context,
                                      (lat: c.lat, lon: c.lon),
                                    ),
                              child: Text(l10n.photosPickLocationUse),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
