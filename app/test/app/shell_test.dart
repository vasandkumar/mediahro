import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets(
    'CORE-001 phone shows a bottom bar with Video, Music, Photos, Search, Settings',
    (tester) async {
      await pumpApp(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final label in ['Video', 'Music', 'Photos', 'Search', 'Settings']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('CORE-001 tablet/desktop shows a sidebar including Sources', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Sources'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('CORE-001 switching modes changes the destination and accent', (
    tester,
  ) async {
    await pumpApp(tester);
    final videoPrimary = Theme.of(tester.element(find.byType(NavigationBar)))
        .colorScheme
        .primary;
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Music'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Music arrives in milestone M4.'), findsOneWidget);
    final musicPrimary = Theme.of(tester.element(find.byType(NavigationBar)))
        .colorScheme
        .primary;
    expect(musicPrimary, isNot(videoPrimary));
  });

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
    },
  );

  testWidgets(
    'SYS-008 first-run actions meet the 44 pt target, are labelled and have contrast',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      for (final label in ['Open a file', 'Add a folder', 'Add a server']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        expect(tester.getSize(button.first).height, greaterThanOrEqualTo(44));
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    },
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

  testWidgets('SYS-008 layout survives 200 percent text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Open a file'), findsOneWidget);
  });
}
