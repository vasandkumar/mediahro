import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/map/gazetteer.dart';
import 'package:mediahro/features/photos/map/gazetteer_providers.dart';
import 'package:mediahro/features/photos/map/geo_point.dart';

/// A position the user chose.
typedef PickedLocation = ({double lat, double lon});

/// Opens the location chooser and returns the position, or null when the
/// user backed out (IMG-007 set location).
Future<PickedLocation?> pickLocation(
  BuildContext context, {
  GeoPoint? initial,
}) => Navigator.of(context).push<PickedLocation>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => LocationPickerScreen(initial: initial),
  ),
);

/// `48.85661, 2.35222`: five decimals are about a metre.
String formatPosition(GeoPoint p) =>
    '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';

/// Choose a place by searching the offline gazetteer, or type latitude and
/// longitude; nothing is sent anywhere.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({this.initial, super.key});

  final GeoPoint? initial;

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final TextEditingController _query = TextEditingController();
  late final TextEditingController _coords = TextEditingController(
    text: widget.initial == null ? '' : formatPosition(widget.initial!),
  );
  List<GazetteerPlace> _matches = const [];
  GazetteerPlace? _place;

  @override
  void dispose() {
    _query.dispose();
    _coords.dispose();
    super.dispose();
  }

  GeoPoint? get _position => parsePosition(_coords.text);

  void _search(String text) {
    final g = ref.read(gazetteerProvider).value;
    setState(() => _matches = g?.search(text) ?? const []);
  }

  void _choose(GazetteerPlace p) {
    FocusScope.of(context).unfocus();
    _query.clear();
    _coords.text = formatPosition((lat: p.latitude, lon: p.longitude));
    setState(() {
      _matches = const [];
      _place = p;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasSearch = ref.watch(gazetteerProvider).value != null;
    final typed = _coords.text.trim().isNotEmpty;
    final position = _position;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.photosPickLocationTitle),
        leading: IconButton(
          tooltip: l10n.photosPickLocationClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.photosPickLocationHint, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            if (hasSearch) ...[
              TextField(
                controller: _query,
                onChanged: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l10n.photosPickLocationSearch,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
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
                                onTap: () => _choose(p),
                              ),
                          ],
                        ),
                ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _coords,
              onChanged: (_) => setState(() => _place = null),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.photosPickLocationCoordinates,
                helperText: l10n.photosPickLocationCoordinatesHelp,
                errorText: typed && position == null
                    ? l10n.photosPickLocationInvalid
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (position != null && _place != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.photosPickLocationPlace(_place!.name, _place!.country),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: position == null
                  ? null
                  : () => Navigator.pop<PickedLocation>(context, position),
              child: Text(l10n.photosPickLocationUse),
            ),
          ],
        ),
      ),
    );
  }
}
