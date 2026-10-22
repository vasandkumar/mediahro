import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/features/library/search_screen.dart';
import 'package:mediahro/features/music/music_home_screen.dart';
import 'package:mediahro/features/photos/photos_home_screen.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_screen.dart';
import 'package:mediahro/features/sources/sources_screen.dart';
import 'package:mediahro/features/video/video_home_screen.dart';
import 'package:mediahro/ui/adaptive_shell.dart';
import 'package:mediahro_design/mediahro_design.dart';

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

  /// The three media modes, restored on launch (CORE-001).
  static const List<AppDestination> modes = [video, music, photos];

  static bool isMode(String name) => modes.any((m) => m.name == name);

  MediaMode? get mediaMode => switch (this) {
    video => MediaMode.video,
    music => MediaMode.music,
    photos => MediaMode.photos,
    _ => null,
  };
}

/// Routes owned by other lanes are reached by location only:
/// - `/sources?add=folder|server` (B2, first-run actions),
/// - `/video?open=file|url` (C1, open a file or stream).
abstract final class AppRoutes {
  static const String settingsPrivacy = '/settings/privacy';
  static const String settingsShortcuts = '/settings/shortcuts';
  static const String addFolder = '/sources?add=folder';
  static const String addServer = '/sources?add=server';
  static const String openFile = '/video?open=file';
  static const String openUrl = '/video?open=url';
}

/// Full-screen routes outside the shell, contributed by the lanes that own
/// them from their own folders: the video player (C1), Now Playing (C2),
/// the photo viewer and compare (C3). They cover the navigation bar and the
/// mini-player. The orchestrator lists them in main.dart:
/// `appRoutesProvider.overrideWithValue([...videoRoutes, ...musicRoutes])`.
/// Paths must not start with a shell destination's path segment alone
/// (use `/play`, `/now-playing`, `/photos/view/:id` style paths).
final appRoutesProvider = Provider<List<RouteBase>>((ref) => const []);

GoRouter buildRouter({
  String initialLocation = '/video',
  List<RouteBase> fullScreenRoutes = const [],
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ...fullScreenRoutes,
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AdaptiveShell(shell: shell),
      branches: [
        for (final d in AppDestination.values)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: d.path,
                builder: (context, state) => _screenFor(d, state),
                routes: [
                  if (d == AppDestination.settings)
                    GoRoute(
                      path: ':section',
                      builder: (context, state) => SettingsScreen(
                        section: SettingsSectionId.values
                            .asNameMap()[state.pathParameters['section']],
                      ),
                    ),
                ],
              ),
            ],
          ),
      ],
    ),
  ],
);

Widget _screenFor(AppDestination d, GoRouterState state) => switch (d) {
  AppDestination.video => const VideoHomeScreen(),
  AppDestination.music => const MusicHomeScreen(),
  AppDestination.photos => const PhotosHomeScreen(),
  // `?q=` starts a search (a shared text, a voice search, SYS-003/004).
  AppDestination.search => SearchScreen(
    key: ValueKey(state.uri.queryParameters['q']),
    initialQuery: state.uri.queryParameters['q'],
  ),
  AppDestination.settings => const SettingsScreen(),
  AppDestination.sources => const SourcesScreen(),
};
