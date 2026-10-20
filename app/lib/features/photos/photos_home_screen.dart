import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photos_timeline.dart';
import 'package:mediahro/ui/pending_screen.dart';

/// The Photos destination (IMG-003): the timeline over the library index.
class PhotosHomeScreen extends ConsumerWidget {
  const PhotosHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(photosLibraryAvailableProvider)
      ? const PhotoTimeline()
      // No library database (shell-only builds and tests): the pending
      // placeholder the shell showed before M5.
      : PendingScreen(
          title: AppLocalizations.of(context).appNavPhotos,
          milestone: 'M5',
        );
}
