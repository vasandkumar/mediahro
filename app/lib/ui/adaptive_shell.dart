import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Width at which the phone bottom bar becomes a sidebar (window size class
/// "medium", SYS-011).
const double kSidebarBreakpoint = 600;

/// Three-mode shell (CORE-001): bottom bar on phones, sidebar on tablets and
/// desktop. Each mode carries its own accent (docs/03 §3.3).
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  AppDestination get _current => AppDestination.values[shell.currentIndex];

  MediaMode get _mode => switch (_current) {
    AppDestination.music => MediaMode.music,
    AppDestination.photos => MediaMode.photos,
    _ => MediaMode.video,
  };

  void _go(AppDestination d) =>
      shell.goBranch(d.index, initialLocation: d == _current);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final family = platformFamilyFor(defaultTargetPlatform);
    final modeTheme = MediahroTheme.build(
      ThemeSpec(family: family, brightness: theme.brightness, mode: _mode),
    );
    final wide = MediaQuery.sizeOf(context).width >= kSidebarBreakpoint;

    String label(AppDestination d) => switch (d) {
      AppDestination.video => l10n.appNavVideo,
      AppDestination.music => l10n.appNavMusic,
      AppDestination.photos => l10n.appNavPhotos,
      AppDestination.search => l10n.appNavSearch,
      AppDestination.settings => l10n.appNavSettings,
      AppDestination.sources => l10n.appNavSources,
    };

    KIcon icon(AppDestination d) => switch (d) {
      AppDestination.video => KIcon.video,
      AppDestination.music => KIcon.music,
      AppDestination.photos => KIcon.photos,
      AppDestination.search => KIcon.search,
      AppDestination.settings => KIcon.settings,
      AppDestination.sources => KIcon.sources,
    };

    final body = AnimatedTheme(
      data: modeTheme,
      duration: KMotion.resolve(
        KMotion.base,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
      child: shell,
    );

    if (!wide) {
      const bar = AppDestination.phoneBar;
      final selected = bar.indexOf(_current);
      return Scaffold(
        body: body,
        bottomNavigationBar: Theme(
          data: modeTheme,
          child: NavigationBar(
            selectedIndex: selected < 0
                ? bar.indexOf(AppDestination.settings)
                : selected,
            onDestinationSelected: (i) => _go(bar[i]),
            destinations: [
              for (final d in bar)
                NavigationDestination(
                  icon: Icon(icon(d).resolve(family)),
                  label: label(d),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Theme(
            data: modeTheme,
            child: NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1000,
              labelType: MediaQuery.sizeOf(context).width >= 1000
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedIndex: _current.index,
              onDestinationSelected: (i) => _go(AppDestination.values[i]),
              destinations: [
                for (final d in AppDestination.values)
                  NavigationRailDestination(
                    icon: Icon(icon(d).resolve(family)),
                    label: Text(label(d)),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
