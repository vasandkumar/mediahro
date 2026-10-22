import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/features/photos/organise/photo_collection_view.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_access_banner.dart';
import 'package:mediahro/features/photos/timeline/source_filter.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/sources/sources_screen.dart'
    show addDeviceMediaFlow;
import 'package:mediahro_design/mediahro_design.dart';

/// The timeline tab (IMG-003): every photo and video, newest first, with
/// selection for organising (IMG-005).
class TimelineTab extends ConsumerWidget {
  const TimelineTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final body = ref
        .watch(photoEntriesProvider)
        .when(
          data: (list) => list.isEmpty
              ? KEmptyState(
                  title: l10n.photosEmptyTitle,
                  message: l10n.photosEmptyMessage,
                  actions: [
                    // The device's own pictures (screenshots, camera) are
                    // not in a folder the user would think to pick.
                    if (defaultTargetPlatform == TargetPlatform.android)
                      KButton(
                        label: l10n.photosAddDevice,
                        variant: KButtonVariant.primary,
                        onPressed: () =>
                            unawaited(addDeviceMediaFlow(context, ref)),
                      ),
                    KButton(
                      label: l10n.photosAddPhotos,
                      onPressed: () => context.go(AppRoutes.addFolder),
                    ),
                  ],
                )
              : _WithSources(list: list),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => KErrorState(
            message: l10n.photosLoadFailedTitle,
            action: KButton(
              label: l10n.photosRetry,
              onPressed: () => ref.invalidate(photoEntriesProvider),
            ),
          ),
        );
    // Partial or refused access to the device's pictures is said above the
    // timeline (IMG-016).
    return Column(
      children: [
        const PhotoAccessBanner(),
        Expanded(child: body),
      ],
    );
  }
}

/// The grid, with the source chips above it when photos come from more than
/// one source (IMG-016).
class _WithSources extends ConsumerWidget {
  const _WithSources({required this.list});

  final List<PhotoEntry> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sources = timelineSources(
      list,
      ref.watch(sourceSummariesProvider).value ?? const <SourceSummary>[],
      l10n.photosSourceUnnamed,
    );
    final selected = ref.watch(photoSourceFilterProvider);
    final view = PhotoCollectionView(
      entries: filterBySource(list, selected, sources),
      emptyMessage: l10n.photosEmptyMessage,
    );
    if (sources.length < 2) return view;
    return Column(
      children: [
        SourceFilterBar(
          sources: sources,
          selected: sources.any((s) => s.id == selected) ? selected : null,
          onSelect: (id) =>
              ref.read(photoSourceFilterProvider.notifier).source = id,
        ),
        Expanded(child: view),
      ],
    );
  }
}
