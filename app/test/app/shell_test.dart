import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/app/locales.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/ui/mini_player_slot.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_design/testing.dart';

import '../helpers.dart';

Finder _barLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets(
    'CORE-001 phone shows a bottom bar with Video, Music, Photos, Search, Settings',
    (tester) async {
      await pumpApp(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(KSidebar), findsNothing);
      for (final label in ['Video', 'Music', 'Photos', 'Search', 'Settings']) {
        expect(_barLabel(label), findsOneWidget);
      }
    },
  );

  testWidgets('CORE-001 tablet/desktop shows a sidebar including Sources', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1280, 800));
    expect(find.byType(KSidebar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.descendant(
        of: find.byType(KSidebar),
        matching: find.text('Sources'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SYS-011 sidebar collapses on medium windows, extends on large', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(700, 800));
    expect(tester.widget<KSidebar>(find.byType(KSidebar)).extended, isFalse);
    await pumpApp(tester, size: const Size(1400, 800));
    expect(tester.widget<KSidebar>(find.byType(KSidebar)).extended, isTrue);
  });

  testWidgets('CORE-001 switching modes changes the destination and accent', (
    tester,
  ) async {
    await pumpApp(tester);
    final videoPrimary = Theme.of(tester.element(find.byType(NavigationBar)))
        .colorScheme
        .primary;
    await tester.tap(_barLabel('Music'));
    await tester.pumpAndSettle();
    expect(find.text('Music arrives in milestone M4.'), findsOneWidget);
    final musicPrimary = Theme.of(tester.element(find.byType(NavigationBar)))
        .colorScheme
        .primary;
    expect(musicPrimary, isNot(videoPrimary));
  });

  testWidgets('CORE-001 the mode in use is remembered for the next launch', (
    tester,
  ) async {
    final store = await pumpApp(tester, initialLocation: null);
    await tester.tap(_barLabel('Photos'));
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.lastMode), 'photos');
    await tester.tap(_barLabel('Search'));
    await tester.pumpAndSettle();
    expect(store.get(CoreSettings.lastMode), 'photos');
  });

  testWidgets('CORE-001 last mode is restored on launch', (tester) async {
    final store = await tester.runAsync(
      () => memoryStore({'shell.lastMode': 'music'}),
    );
    await pumpApp(tester, settings: store, initialLocation: null);
    expect(find.text('Music arrives in milestone M4.'), findsOneWidget);
  });

  testWidgets('CORE-001 restoring can be turned off', (tester) async {
    final store = await tester.runAsync(
      () => memoryStore({
        'shell.lastMode': 'music',
        'appearance.restoreLastMode': false,
      }),
    );
    await pumpApp(tester, settings: store, initialLocation: null);
    expect(find.text('Open a file'), findsOneWidget);
  });

  testWidgets('CORE-001 mini-player slot sits above the bar when filled', (
    tester,
  ) async {
    await pumpApp(
      tester,
      overrides: [
        miniPlayerSlotProvider.overrideWithValue(
          (context) => const SizedBox(key: Key('mini'), height: 64),
        ),
      ],
    );
    final mini = tester.getRect(find.byKey(const Key('mini')));
    final bar = tester.getRect(find.byType(NavigationBar));
    expect(mini.bottom, lessThanOrEqualTo(bar.top));
  });

  testWidgets('CORE-007 Apple bars use glass; reduced transparency is solid', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      find.descendant(
        of: find.byType(KBarSurface),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    final store = await tester.runAsync(
      () => memoryStore({'appearance.reduceTransparency': 'on'}),
    );
    await pumpApp(tester, settings: store);
    expect(find.byType(BackdropFilter), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('CORE-007 Windows shell is transparent when Mica is active', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(1280, 800),
      overrides: [
        platformAppearanceProvider.overrideWithValue(
          const PlatformAppearance(micaActive: true),
        ),
      ],
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, Colors.transparent);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('CORE-007 Android uses predictive back page transitions', (
    tester,
  ) async {
    await pumpApp(tester);
    final theme = Theme.of(tester.element(find.byType(NavigationBar)));
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<PredictiveBackPageTransitionsBuilder>(),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'CORE-002 first screen offers the three actions and the privacy line, no walls',
    (tester) async {
      await pumpApp(tester);
      expect(find.text('Open a file'), findsOneWidget);
      expect(find.text('Add a folder'), findsOneWidget);
      expect(find.text('Add a server'), findsOneWidget);
      expect(
        find.text('Privacy: nothing leaves this device unless you turn it on'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets('PRIV-001 first run says the three telemetry switches are off', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      find.textContaining('Crash reports, usage statistics and update checks'),
      findsOneWidget,
    );
  });

  testWidgets(
    'SYS-008 shell meets target size, labels and contrast per platform',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await expectAccessible(tester, platformFamilyFor(defaultTargetPlatform));
      handle.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('CORE-008 RTL locale lays the shell out right-to-left', (
    tester,
  ) async {
    await pumpApp(tester, locale: const Locale('ar'));
    expect(
      Directionality.of(tester.element(find.byType(NavigationBar))),
      TextDirection.rtl,
    );
  });

  testWidgets('CORE-008 pseudo-locales: expanded strings and RTL render', (
    tester,
  ) async {
    await pumpApp(tester, locale: pseudoExpanded, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Open a file'), findsNothing);
    await pumpApp(tester, locale: pseudoRtl);
    expect(
      Directionality.of(tester.element(find.byType(NavigationBar))),
      TextDirection.rtl,
    );
  });

  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets('SYS-008 layout survives 200 percent text at $size', (
      tester,
    ) async {
      await pumpApp(tester, size: size, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Open a file'), findsOneWidget);
    });
  }
}
