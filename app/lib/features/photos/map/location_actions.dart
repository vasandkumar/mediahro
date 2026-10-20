import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/map/location_picker.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';

/// How a bulk location change went.
typedef LocationOutcome = ({int changed, int failed});

/// Sets ([location]) or removes (null) the location of [photos], one file at
/// a time so one unreadable file does not stop the rest. [onProgress] gets
/// the number done so far.
Future<LocationOutcome> changeLocation(
  MetadataEditor editor,
  List<PhotoEntry> photos, {
  PickedLocation? location,
  void Function(int done)? onProgress,
}) async {
  final edit = location == null
      ? const ImageMetadataEdit(clearLocation: true)
      : ImageMetadataEdit(location: (location.lat, location.lon));
  var changed = 0;
  var failed = 0;
  for (final p in photos) {
    try {
      await editor.save(p, edit);
      changed++;
    } on Object {
      failed++;
    }
    onProgress?.call(changed + failed);
  }
  return (changed: changed, failed: failed);
}

/// Picks a place on the map and writes it into the selected photos
/// (IMG-007). Videos are left alone. Returns true when something changed.
Future<bool> setLocationFlow(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> chosen,
) async {
  final photos = chosen.where((e) => !e.isVideo).toList();
  if (photos.isEmpty) return _nothing(context);
  final spot = await pickLocation(context);
  if (spot == null || !context.mounted) return false;
  return await _apply(context, ref, photos, spot);
}

/// Removes the location of the selected photos after a confirmation.
Future<bool> clearLocationFlow(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> chosen,
) async {
  final photos = chosen.where((e) => !e.isVideo).toList();
  if (photos.isEmpty) return _nothing(context);
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.photosClearLocationTitle),
      content: Text(l10n.photosClearLocationBody(photos.length)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.photosClearLocationConfirm),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return await _apply(context, ref, photos, null);
}

bool _nothing(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(AppLocalizations.of(context).photosLocationNoPhotos),
    ),
  );
  return false;
}

Future<bool> _apply(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> photos,
  PickedLocation? spot,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final done = ValueNotifier<int>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: done,
            builder: (context, n, _) => Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.photosLocationProgress(n, photos.length)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: n / photos.length),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final LocationOutcome result;
  try {
    result = await changeLocation(
      ref.read(metadataEditServiceProvider),
      photos,
      location: spot,
      onProgress: (n) => done.value = n,
    );
  } finally {
    navigator.pop();
    done.dispose();
  }
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        [
          if (result.changed > 0) l10n.photosLocationDone(result.changed),
          if (result.failed > 0) l10n.photosLocationFailed(result.failed),
        ].join(' '),
      ),
    ),
  );
  return result.changed > 0;
}
