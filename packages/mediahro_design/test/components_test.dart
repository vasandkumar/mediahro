import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_design/testing.dart';

import 'specimens.dart';

void main() {
  group('SYS-008 accessibility sweep', () {
    for (final family in PlatformFamily.values) {
      for (final brightness in Brightness.values) {
        for (final entry in specimens.entries) {
          testWidgets(
            '${entry.key} ${family.name}/${brightness.name}: targets, labels, contrast',
            (tester) async {
              final handle = tester.ensureSemantics();
              await pumpK(
                tester,
                SingleChildScrollView(child: Builder(builder: entry.value)),
                family: family,
                brightness: brightness,
                settle: false,
              );
              await expectAccessible(tester, family);
              handle.dispose();
            },
          );
        }
      }
    }
  });

  group('SYS-008 200 % text and RTL never overflow', () {
    for (final entry in specimens.entries) {
      for (final dir in TextDirection.values) {
        testWidgets('${entry.key} at 2.0× ${dir.name}', (tester) async {
          await pumpK(
            tester,
            SingleChildScrollView(child: Builder(builder: entry.value)),
            variant: KVariant(2, dir),
            size: const Size(360, 1600),
            settle: false,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('KButton', () {
    testWidgets('SYS-008 meets the 48 dp Material and 44 pt Apple targets', (
      tester,
    ) async {
      for (final (family, min) in [
        (PlatformFamily.material, 48.0),
        (PlatformFamily.apple, 44.0),
        (PlatformFamily.fluent, 44.0),
      ]) {
        await pumpK(
          tester,
          Center(
            child: KButton(label: 'Go', onPressed: () {}),
          ),
          family: family,
        );
        final size = tester.getSize(find.byType(OutlinedButton));
        expect(size.height, greaterThanOrEqualTo(min));
        expect(size.width, greaterThanOrEqualTo(min));
      }
    });

    testWidgets('SYS-008 label wraps at 200 % instead of truncating', (
      tester,
    ) async {
      await pumpK(
        tester,
        KButton(
          label: 'Add a network share or media server',
          expand: true,
          onPressed: () {},
        ),
        variant: const KVariant(2, TextDirection.ltr),
        size: const Size(240, 600),
      );
      final p = tester.renderObject<RenderParagraph>(
        find.text('Add a network share or media server'),
      );
      expect(p.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SYS-008 icon buttons announce label and toggle state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpK(
        tester,
        KIconButton(
          icon: KIcon.subtitles,
          label: 'Subtitles',
          selected: true,
          onPressed: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byTooltip('Subtitles')),
        isSemantics(
          tooltip: 'Subtitles',
          isButton: true,
          isEnabled: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('KSeekBar', () {
    Widget bar(ValueChanged<Duration> onSeek) => KSeekBar(
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 100),
      onSeek: onSeek,
    );

    testWidgets('SYS-008 reads "10:00 of 1:40:00" and steps 1 %', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      Duration? sought;
      await pumpK(tester, bar((d) => sought = d));
      final node = tester.getSemantics(find.byType(KSeekBar));
      expect(node.label, 'Seek');
      expect(node.value, '0:10:00 of 1:40:00');
      tester.semantics.performAction(
        find.semantics.byLabel('Seek'),
        SemanticsAction.increase,
      );
      expect(sought, const Duration(minutes: 11));
      handle.dispose();
    });

    testWidgets('SYS-008 offers ±10 % custom actions', (tester) async {
      final handle = tester.ensureSemantics();
      Duration? sought;
      await pumpK(tester, bar((d) => sought = d));
      final node = tester.getSemantics(find.byType(KSeekBar));
      final data = node.getSemanticsData();
      expect(data.customSemanticsActionIds, hasLength(2));
      handle.dispose();
      expect(sought, isNull);
    });

    testWidgets('CORE-009 keyboard: arrows 1 %, Page Up 10 %', (tester) async {
      Duration? sought;
      await pumpK(tester, bar((d) => sought = d));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(sought, const Duration(minutes: 11));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      expect(sought, const Duration(minutes: 20));
    });

    testWidgets('tap seeks to the tapped fraction; drag scrubs then seeks', (
      tester,
    ) async {
      Duration? sought;
      final updates = <Duration>[];
      await pumpK(
        tester,
        SizedBox(
          width: 400,
          child: KSeekBar(
            position: Duration.zero,
            duration: const Duration(seconds: 400),
            onSeek: (d) => sought = d,
            onScrubUpdate: updates.add,
          ),
        ),
      );
      final box = tester.getRect(find.byType(KSeekBar));
      await tester.tapAt(box.centerLeft + const Offset(100, 0));
      expect(sought!.inSeconds, closeTo(100, 1));
      await tester.dragFrom(
        box.centerLeft + const Offset(10, 0),
        const Offset(190, 0),
      );
      expect(updates, isNotEmpty);
      expect(sought!.inSeconds, closeTo(200, 2));
    });

    testWidgets('CORE-008 stays left-to-right in RTL locales', (tester) async {
      Duration? sought;
      await pumpK(
        tester,
        SizedBox(
          width: 400,
          child: KSeekBar(
            position: Duration.zero,
            duration: const Duration(seconds: 400),
            onSeek: (d) => sought = d,
          ),
        ),
        variant: const KVariant(1, TextDirection.rtl),
      );
      final box = tester.getRect(find.byType(KSeekBar));
      await tester.tapAt(box.centerLeft + const Offset(40, 0));
      expect(sought!.inSeconds, lessThan(60));
    });
  });

  group('KSheet', () {
    testWidgets('bottom sheet on phones, side sheet on wide windows', (
      tester,
    ) async {
      for (final (size, side) in [
        (const Size(400, 800), false),
        (const Size(1200, 800), true),
      ]) {
        await pumpK(
          tester,
          Builder(
            builder: (context) => KButton(
              label: 'Open',
              onPressed: () => KSheet.show<void>(
                context,
                title: 'Audio',
                builder: (_) => const Text('Tracks'),
              ),
            ),
          ),
          size: size,
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Tracks'), findsOneWidget);
        expect(find.byType(BottomSheet), side ? findsNothing : findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Tracks'), findsNothing);
      }
    });

    testWidgets('SYS-008 reduced motion presents with a crossfade only', (
      tester,
    ) async {
      await pumpK(
        tester,
        Builder(
          builder: (context) => KButton(
            label: 'Open',
            onPressed: () => KSheet.show<void>(
              context,
              title: 'Audio',
              placement: KSheetPlacement.side,
              builder: (_) => const Text('Tracks'),
            ),
          ),
        ),
        size: const Size(1200, 800),
        variant: const KVariant(1, TextDirection.ltr, reduced: true),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.ancestor(
          of: find.text('Tracks'),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
    });
  });

  group('KGrid', () {
    test('SYS-011 density: 1–6 columns on phones, up to 12 on desktop', () {
      expect(kGridColumns(width: 360), 2);
      expect(kGridColumns(width: 360, columns: 9), 6);
      expect(kGridColumns(width: 2000, columns: 20), 12);
      expect(kGridColumns(width: 100), 1);
    });
  });

  group('KSidebar', () {
    testWidgets(
      'SYS-008 collapsed items keep their labels for screen readers',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpK(
          tester,
          SizedBox(
            height: 400,
            child: Row(
              children: [
                KSidebar(
                  selectedIndex: 0,
                  onSelected: (_) {},
                  items: const [
                    KSidebarItem(icon: KIcon.video, label: 'Video'),
                    KSidebarItem(icon: KIcon.music, label: 'Music'),
                  ],
                ),
              ],
            ),
          ),
          family: PlatformFamily.apple,
        );
        expect(find.bySemanticsLabel('Music'), findsOneWidget);
        handle.dispose();
      },
    );
  });

  group('KPlayerChrome', () {
    testWidgets('SYS-008 stays visible while a screen reader is active', (
      tester,
    ) async {
      await pumpK(
        tester,
        MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: KPlayerChrome(
            video: const SizedBox.expand(),
            visible: false,
            title: 'Film',
            onBack: () {},
          ),
        ),
      );
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 1);
    });

    testWidgets('SYS-008 reduced transparency uses opaque panels', (
      tester,
    ) async {
      await pumpK(
        tester,
        const KPlayerChrome(
          video: SizedBox.expand(),
          visible: true,
          title: 'Film',
        ),
        variant: const KVariant(1, TextDirection.ltr, reduced: true),
      );
      final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      expect(
        boxes.any(
          (b) =>
              b.decoration is BoxDecoration &&
              (b.decoration as BoxDecoration).gradient != null,
        ),
        isFalse,
      );
    });
  });

  group('KSettingsRow', () {
    testWidgets('CORE-006 managed rows are locked and say so', (tester) async {
      var changed = false;
      await pumpK(
        tester,
        KSettingsRow.toggle(
          title: 'Crash reports',
          description: 'Send anonymous crash reports.',
          value: false,
          onChanged: (_) => changed = true,
          managed: true,
        ),
      );
      expect(find.text('Managed by your organisation'), findsOneWidget);
      await tester.tap(find.text('Crash reports'));
      expect(changed, isFalse);
    });

    testWidgets('CORE-006 tapping the row toggles; state is announced', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      bool? value;
      await pumpK(
        tester,
        KSettingsRow.toggle(
          title: 'AMOLED black',
          description: 'Pure black dark theme.',
          value: false,
          onChanged: (v) => value = v,
        ),
      );
      await tester.tap(find.text('AMOLED black'));
      expect(value, isTrue);
      expect(
        tester.getSemantics(find.text('AMOLED black')),
        isSemantics(hasToggledState: true),
      );
      handle.dispose();
    });

    testWidgets('CORE-006 advanced group is collapsed until expanded', (
      tester,
    ) async {
      await pumpK(
        tester,
        KAdvancedGroup(
          children: [
            KSettingsRow.navigation(
              title: 'Engine options',
              description: 'Low-level playback options.',
              onTap: () {},
            ),
          ],
        ),
      );
      expect(find.text('Engine options'), findsNothing);
      await tester.tap(find.text('Show advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Engine options'), findsOneWidget);
    });
  });

  group('KTimelineScrubber', () {
    testWidgets('SYS-008 steps between marks and reads the mark label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      double? f;
      await pumpK(
        tester,
        SizedBox(
          height: 300,
          child: KTimelineScrubber(
            label: 'Timeline',
            fraction: 0.4,
            onChanged: (v) => f = v,
            marks: const [
              KTimelineMark(label: '2026', fraction: 0),
              KTimelineMark(label: '2025', fraction: 0.35),
              KTimelineMark(label: '2024', fraction: 0.7),
            ],
          ),
        ),
      );
      expect(tester.getSemantics(find.byType(KTimelineScrubber)).value, '2025');
      tester.semantics.performAction(
        find.semantics.byLabel('Timeline'),
        SemanticsAction.increase,
      );
      expect(f, 0.7);
      handle.dispose();
    });
  });

  group('KSkeletonRows', () {
    testWidgets('SYS-008 announces loading; static under reduced motion', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpK(
        tester,
        const KSkeletonRows(count: 2),
        variant: const KVariant(1, TextDirection.ltr, reduced: true),
      );
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      handle.dispose();
    });
  });

  group('format', () {
    test('docs/06 §8 durations as 1:23:45', () {
      expect(formatMediaDuration(const Duration(seconds: 5)), '0:05');
      expect(
        formatMediaDuration(const Duration(minutes: 3, seconds: 7)),
        '3:07',
      );
      expect(
        formatMediaDuration(const Duration(hours: 1, minutes: 23, seconds: 45)),
        '1:23:45',
      );
      expect(
        formatMediaDuration(
          const Duration(minutes: 5),
          reference: const Duration(hours: 2),
        ),
        '0:05:00',
      );
      expect(
        formatRemaining(const Duration(minutes: 1), const Duration(minutes: 4)),
        '−3:00',
      );
    });
  });

  group('SYS-011 adaptive', () {
    test('window classes follow Material breakpoints', () {
      expect(KWindowClass.forWidth(400), KWindowClass.compact);
      expect(KWindowClass.forWidth(700), KWindowClass.medium);
      expect(KWindowClass.forWidth(900), KWindowClass.expanded);
      expect(KWindowClass.forWidth(1300), KWindowClass.large);
      expect(KWindowClass.forWidth(1700), KWindowClass.extraLarge);
      expect(KWindowClass.compact.usesSidebar, isFalse);
      expect(KWindowClass.medium.usesSidebar, isTrue);
    });

    testWidgets('list-detail shows both panes from expanded', (tester) async {
      for (final (w, both) in [(500.0, false), (1000.0, true)]) {
        await pumpK(
          tester,
          const KListDetail(list: Text('List'), detail: Text('Detail')),
          size: Size(w, 600),
        );
        expect(find.text('Detail'), both ? findsOneWidget : findsNothing);
      }
    });
  });
}
