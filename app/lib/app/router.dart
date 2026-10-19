import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/features/library/search_screen.dart';
import 'package:mediahro/features/music/music_home_screen.dart';
import 'package:mediahro/features/photos/photos_home_screen.dart';
import 'package:mediahro/features/settings/settings_screen.dart';
import 'package:mediahro/features/sources/sources_screen.dart';
import 'package:mediahro/features/video/video_home_screen.dart';
import 'package:mediahro/ui/adaptive_shell.dart';

/// Top-level destinations in shell order (docs/06 §2). The first five are the
/// phone bottom bar; [sources] appears in the tablet/desktop sidebar and is
/// reachable from Settings on phones.
enum AppDestination {
  video('/video'),
  music('/music'),
  photos('/photos'),
  search('/search'),
  settings('/settings'),
  sources('/sources');

  const AppDestination(this.path);

  final String path;

  static const List<AppDestination> phoneBar = [
    video,
    music,
    photos,
    search,
    settings,
  ];
}

GoRouter buildRouter({String initialLocation = '/video'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AdaptiveShell(shell: shell),
      branches: [
        for (final d in AppDestination.values)
          StatefulShellBranch(
            routes: [
              GoRoute(path: d.path, builder: (context, state) => _screenFor(d)),
            ],
          ),
      ],
    ),
  ],
);

Widget _screenFor(AppDestination d) => switch (d) {
  AppDestination.video => const VideoHomeScreen(),
  AppDestination.music => const MusicHomeScreen(),
  AppDestination.photos => const PhotosHomeScreen(),
  AppDestination.search => const SearchScreen(),
  AppDestination.settings => const SettingsScreen(),
  AppDestination.sources => const SourcesScreen(),
};
