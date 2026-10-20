import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/providers.dart';

/// Explains what the map-picture switch sends, and turns it on if the user
/// agrees (IMG-007: the only network use of the map, off until then).
Future<void> askToTurnOnMapTiles(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.photosMapTilesConfirmTitle),
      content: Text(l10n.photosMapTilesConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.photosMapTilesConfirmYes),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref
      .read(networkPolicyProvider)
      .setEnabled(Endpoints.mapTiles, enabled: true);
}

/// The note shown over the map while map pictures are off.
class MapTilesOffCard extends ConsumerWidget {
  const MapTilesOffCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.photosMapTilesOff),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => unawaited(askToTurnOnMapTiles(context, ref)),
                child: Text(l10n.photosMapTilesTurnOn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
