import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/features/library/library_widgets.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro/features/onboarding/first_run_panel.dart';
import 'package:mediahro/features/sources/open_url_dialog.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The library the video home lists; null without one (widget tests, a
/// build whose database failed to open). `videoOverrides` points it at
/// `libraryDatabaseProvider`.
final videoLibraryProvider = Provider<LibraryDatabase?>((ref) => null);

/// Every indexed video, by title (the video home's list).
final allVideosProvider = StreamProvider<List<ItemRow>>((ref) {
  final db = ref.watch(videoLibraryProvider);
  if (db == null) return Stream.value(const []);
  return (db.select(db.items)
        ..where(
          (i) =>
              i.kind.equalsValue(ItemKind.video) &
              i.missing.equals(false) &
              i.hidden.equals(false) &
              i.vault.equals(false),
        )
        ..orderBy([(i) => OrderingTerm.asc(i.title)])
        ..limit(2000))
      .watch();
});

/// Video home (docs/06 §2): continue watching, recently added and unwatched
/// rows (LIB-006), then every video. With an empty library it is the
/// first-run screen (CORE-002). `/video?open=file|url` (first-run actions)
/// opens the picker or the Open URL dialog.
class VideoHomeScreen extends ConsumerStatefulWidget {
  const VideoHomeScreen({super.key});

  @override
  ConsumerState<VideoHomeScreen> createState() => _VideoHomeScreenState();
}

class _VideoHomeScreenState extends ConsumerState<VideoHomeScreen> {
  String? _handled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final open = GoRouterState.of(context).uri.queryParameters['open'];
    if (open == null || open == _handled) return;
    _handled = open;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Clear the query so back/forward does not reopen the picker.
      context.go('/video');
      switch (open) {
        case 'file':
          unawaited(pickAndPlayVideo(context));
        case 'url':
          unawaited(showOpenUrlDialog(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final videos = ref.watch(allVideosProvider).value ?? const [];
    final hasLibrary = videos.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appNavVideo),
        actions: [
          KIconButton(
            icon: KIcon.openFile,
            label: l.videoOpenFile,
            onPressed: () => unawaited(pickAndPlayVideo(context)),
          ),
          KIconButton(
            icon: KIcon.link,
            label: l.videoOpenUrl,
            onPressed: () => unawaited(showOpenUrlDialog(context)),
          ),
        ],
      ),
      body: !hasLibrary
          ? const FirstRunPanel()
          : CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: HomeRow.continueWatching(mode: LibraryMode.video),
                ),
                const SliverToBoxAdapter(
                  child: HomeRow.recentlyAdded(mode: LibraryMode.video),
                ),
                const SliverToBoxAdapter(
                  child: HomeRow.unwatched(mode: LibraryMode.video),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KSpacing.s16,
                      KSpacing.s16,
                      KSpacing.s16,
                      KSpacing.s8,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l.videoAllVideos,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: videos.length,
                  itemBuilder: (context, i) {
                    final item = videos[i];
                    return ItemTile(
                      item: item,
                      onTap: () => unawaited(openVideoItem(context, item)),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
