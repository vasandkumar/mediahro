import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/places_providers.dart';
import 'package:mediahro/features/photos/organise/photo_collection_view.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_layout.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The Places tab (IMG-005, IMG-007): cities grouped by country, named on
/// the device from the photos' GPS positions.
class PlacesTab extends ConsumerStatefulWidget {
  const PlacesTab({super.key});

  @override
  ConsumerState<PlacesTab> createState() => _PlacesTabState();
}

class _PlacesTabState extends ConsumerState<PlacesTab> {
  late final ThumbnailController _thumbs;

  @override
  void initState() {
    super.initState();
    _thumbs = ThumbnailController(ref.read(thumbnailSourceProvider(256)));
  }

  @override
  void dispose() {
    _thumbs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final places = ref.watch(photoPlacesProvider).value;
    final entries = ref.watch(photoEntriesProvider).value;
    if (places == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (places.isEmpty) {
      return KEmptyState(
        title: l10n.photosPlacesEmptyTitle,
        message: l10n.photosPlacesEmptyMessage,
      );
    }
    final byId = {for (final e in entries ?? const <PhotoEntry>[]) e.id: e};
    final rows = <Widget>[];
    String? country;
    var index = 0;
    for (final p in places) {
      final c = p.country ?? l10n.photosPlaceUnknownCountry;
      if (c != country) {
        country = c;
        rows.add(
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
              child: Text(
                c,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        );
      }
      final cover = byId[p.coverId];
      rows.add(
        ListTile(
          leading: SizedBox.square(
            dimension: 48,
            child: ClipOval(
              child: cover == null
                  ? const Icon(Icons.place_outlined)
                  : PhotoThumbnail(
                      entry: cover,
                      index: index,
                      controller: _thumbs,
                      cacheWidth: 96,
                    ),
            ),
          ),
          title: Text(p.name),
          subtitle: Text(l10n.photosFolderCount(p.count)),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => PlaceScreen(place: p)),
          ),
        ),
      );
      index++;
    }
    return ListView(children: rows);
  }
}

/// The photos of one place, as its own screen.
class PlaceScreen extends ConsumerWidget {
  const PlaceScreen({required this.place, super.key});

  final PlaceGroup place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries =
        ref.watch(placeEntriesProvider(place.id)).value ?? const <PhotoEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(place.name),
        actions: const [PhotoLayoutActions()],
      ),
      body: PhotoCollectionView(
        entries: entries,
        emptyMessage: l10n.photosPlacesEmptyMessage,
      ),
    );
  }
}
