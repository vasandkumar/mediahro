import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/features/photos/organise/photo_collection_view.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The timeline tab (IMG-003): every photo and video, newest first, with
/// selection for organising (IMG-005).
class TimelineTab extends ConsumerWidget {
  const TimelineTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(photoEntriesProvider)
        .when(
          data: (list) => list.isEmpty
              ? KEmptyState(
                  title: l10n.photosEmptyTitle,
                  message: l10n.photosEmptyMessage,
                  actions: [
                    KButton(
                      label: l10n.photosAddPhotos,
                      variant: KButtonVariant.primary,
                      onPressed: () => context.go(AppRoutes.addFolder),
                    ),
                  ],
                )
              : PhotoCollectionView(
                  entries: list,
                  emptyMessage: l10n.photosEmptyMessage,
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => KErrorState(
            message: l10n.photosLoadFailedTitle,
            action: KButton(
              label: l10n.photosRetry,
              onPressed: () => ref.invalidate(photoEntriesProvider),
            ),
          ),
        );
  }
}
