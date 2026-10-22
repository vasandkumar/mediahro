import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/features/library/library_widgets.dart';
import 'package:mediahro/features/photos/map/places_tab.dart';
import 'package:mediahro/features/photos/organise/albums_tab.dart';
import 'package:mediahro/features/photos/organise/folders_tab.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_layout.dart';
import 'package:mediahro/features/photos/timeline/photos_timeline.dart';
import 'package:mediahro/ui/pending_screen.dart';

/// The Photos destination: the timeline, albums and folders over the library
/// index (IMG-003, IMG-005).
class PhotosHomeScreen extends ConsumerWidget {
  const PhotosHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (!ref.watch(photosLibraryAvailableProvider)) {
      // No library database (shell-only builds and tests): the pending
      // placeholder the shell showed before M5.
      return PendingScreen(title: l10n.appNavPhotos, milestone: 'M5');
    }
    final folders =
        ref.watch(viewModeProvider(LibraryMode.photos)).value ==
        ViewMode.folders;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.appNavPhotos),
          actions: const [
            ViewModeToggle(mode: LibraryMode.photos),
            PhotoLayoutActions(),
          ],
          // The folder view is one list, so the tabs step aside.
          bottom: folders
              ? null
              : TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: l10n.photosTabTimeline),
                    Tab(text: l10n.photosTabAlbums),
                    Tab(text: l10n.photosTabFolders),
                    Tab(text: l10n.photosTabPlaces),
                  ],
                ),
        ),
        body: folders
            ? const FoldersTab()
            : const TabBarView(
                children: [
                  TimelineTab(),
                  AlbumsTab(),
                  FoldersTab(),
                  PlacesTab(),
                ],
              ),
      ),
    );
  }
}
