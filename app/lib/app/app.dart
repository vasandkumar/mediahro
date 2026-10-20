import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/app_strings.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/locales.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/app/shortcuts/cheat_sheet.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';
import 'package:mediahro/app/shortcuts/shortcut_scope.dart';
import 'package:mediahro/features/onboarding/first_run_actions.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// App root: theme and language from settings (CORE-007, CORE-008), design
/// system scopes, global keyboard shortcuts (CORE-009), and the router that
/// opens in the last used mode (CORE-001).
class MediahroApp extends ConsumerStatefulWidget {
  const MediahroApp({super.key, this.router});

  /// Injected by tests; production builds create the router once settings
  /// have loaded so the initial location can be the last mode.
  final GoRouter? router;

  @override
  ConsumerState<MediahroApp> createState() => _MediahroAppState();
}

class _MediahroAppState extends ConsumerState<MediahroApp> {
  GoRouter? _router;
  AppLifecycleListener? _lifecycle;
  String? _lastMode;

  GoRouter _routerFor(SettingsStore store) {
    if (_router != null) return _router!;
    final restore = store.get(CoreSettings.restoreLastMode);
    final last = store.get(CoreSettings.lastMode);
    final initial = restore && AppDestination.isMode(last)
        ? '/$last'
        : AppDestination.video.path;
    final router =
        widget.router ??
        buildRouter(
          initialLocation: initial,
          fullScreenRoutes: ref.read(appRoutesProvider),
        );
    router.routerDelegate.addListener(() => _rememberMode(router, store));
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(store.flush()),
      onPause: () => unawaited(store.flush()),
    );
    return _router = router;
  }

  /// Records the current mode so the next launch opens there.
  void _rememberMode(GoRouter router, SettingsStore store) {
    final segments =
        router.routerDelegate.currentConfiguration.uri.pathSegments;
    if (segments.isEmpty) return;
    final mode = segments.first;
    if (mode == _lastMode || !AppDestination.isMode(mode)) return;
    _lastMode = mode;
    // Router notifications can arrive mid-build; write after the frame.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => store.set(CoreSettings.lastMode, mode),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Map<String, VoidCallback> _globalHandlers(GoRouter router) {
    BuildContext? nav() => router.routerDelegate.navigatorKey.currentContext;
    final actions = ref.read(firstRunActionsProvider);
    return {
      ShortcutCatalog.cheatSheet: () {
        final c = nav();
        if (c != null) unawaited(showShortcutCheatSheet(c));
      },
      ShortcutCatalog.openSettings: () => router.go('/settings'),
      ShortcutCatalog.search: () => router.go(AppDestination.search.path),
      ShortcutCatalog.modeVideo: () => router.go(AppDestination.video.path),
      ShortcutCatalog.modeMusic: () => router.go(AppDestination.music.path),
      ShortcutCatalog.modePhotos: () => router.go(AppDestination.photos.path),
      ShortcutCatalog.openFile: () {
        final c = nav();
        if (c != null) unawaited(actions.openFile(c));
      },
      ShortcutCatalog.openUrl: () {
        final c = nav();
        if (c != null) unawaited(actions.openUrl(c));
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(settingsStoreProvider);
    final loaded = store.isLoaded || ref.watch(settingsReadyProvider).hasValue;
    if (!loaded) {
      // One frame at most on a warm disk; no spinner (docs/06 §9).
      return const ColoredBox(color: Color(0xFF000000));
    }
    final router = _routerFor(store);
    final theme = ref.watch(themeSettingsProvider);
    final language = ref.watch(
      settingsProvider.select((s) => s.get(CoreSettings.language)),
    );

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: theme.themeMode,
      theme: theme.theme(Brightness.light),
      darkTheme: theme.theme(Brightness.dark),
      highContrastTheme: theme.theme(Brightness.light, highContrast: true),
      highContrastDarkTheme: theme.theme(Brightness.dark, highContrast: true),
      locale: localeFromTag(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => KStringsScope(
        strings: AppKStrings(AppLocalizations.of(context)),
        child: KAccessibility(
          data: theme.accessibility,
          child: ShortcutScopeWidget(
            scope: ShortcutScope.global,
            handlers: _globalHandlers(router),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
