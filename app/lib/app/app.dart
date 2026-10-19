import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro_design/mediahro_design.dart';

class MediahroApp extends ConsumerStatefulWidget {
  const MediahroApp({super.key, this.router});

  /// Injected by tests; production builds create the default router.
  final GoRouter? router;

  @override
  ConsumerState<MediahroApp> createState() => _MediahroAppState();
}

class _MediahroAppState extends ConsumerState<MediahroApp> {
  late final GoRouter _router = widget.router ?? buildRouter();

  @override
  Widget build(BuildContext context) {
    final family = platformFamilyFor(defaultTargetPlatform);
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: MediahroTheme.build(
        ThemeSpec(
          family: family,
          brightness: Brightness.light,
          highContrast: highContrast,
        ),
      ),
      darkTheme: MediahroTheme.build(
        ThemeSpec(
          family: family,
          brightness: Brightness.dark,
          highContrast: highContrast,
        ),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
