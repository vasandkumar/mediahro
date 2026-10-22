import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/perf/mode_switch_probe.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/ui/mini_player_slot.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Width at which the phone bottom bar becomes a sidebar (window size class
/// "medium", SYS-011).
const double kSidebarBreakpoint = 600;

/// Stable key of a destination in the bottom bar or sidebar, independent of
/// form factor and language (tests, UI automation, screenshots).
Key destinationKey(AppDestination d) => ValueKey('nav.${d.name}');

/// Three-mode shell (CORE-001): bottom bar on phones, sidebar on tablets and
/// desktop, each mode with its own accent (docs/03 §3.3). Bars use the
/// platform material (glass on Apple, Mica on Windows, solid Material 3 on
/// Android). The mini-player slot sits above the bar. Back gestures are
/// not intercepted, so Android's predictive back-to-home animation works
/// from every top-level destination.
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  AppDestination get _current => AppDestination.values[shell.currentIndex];

  void _go(AppDestination d) {
    // CORE-001: time the switch to the first frame of the new destination.
    if (d != _current) ModeSwitchProbe.instance.begin(d.name);
    shell.goBranch(d.index, initialLocation: d == _current);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(themeSettingsProvider);
    final mode = _current.mediaMode ?? MediaMode.video;
    final modeTheme = settings.theme(
      theme.brightness,
      mode: mode,
      highContrast: KAccessibility.highContrast(context),
    );
    final family = modeTheme.family;
    final windowClass = KWindowClass.of(context);
    final miniPlayer = ref.watch(miniPlayerSlotProvider)?.call(context);
    final mica =
        family == PlatformFamily.fluent &&
        settings.platform.micaActive &&
        !KAccessibility.reduceTransparency(context);

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
        reduceMotion: KAccessibility.reduceMotion(context),
      ),
      child: shell,
    );

    if (!windowClass.usesSidebar) {
      const bar = AppDestination.phoneBar;
      final selected = bar.indexOf(_current);
      final glass =
          modeTheme.mediahroMaterials.bar == KBarMaterial.glass &&
          !KAccessibility.reduceTransparency(context);
      return Scaffold(
        extendBody: glass,
        backgroundColor: mica ? Colors.transparent : null,
        body: body,
        bottomNavigationBar: Theme(
          data: modeTheme,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?miniPlayer,
              KBarSurface(
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedIndex: selected < 0
                      ? bar.indexOf(AppDestination.settings)
                      : selected,
                  onDestinationSelected: (i) => _go(bar[i]),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    for (final d in bar)
                      NavigationDestination(
                        key: destinationKey(d),
                        icon: Icon(icon(d).resolve(family)),
                        label: label(d),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: mica ? Colors.transparent : null,
      body: Row(
        children: [
          Theme(
            data: modeTheme,
            child: KSidebar(
              extended: windowClass.extendedSidebar,
              selectedIndex: _current.index,
              onSelected: (i) => _go(AppDestination.values[i]),
              items: [
                for (final d in AppDestination.values)
                  KSidebarItem(
                    key: destinationKey(d),
                    icon: icon(d),
                    label: label(d),
                    dividerBefore: d == AppDestination.search,
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: body),
                if (miniPlayer != null)
                  Theme(data: modeTheme, child: miniPlayer),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
