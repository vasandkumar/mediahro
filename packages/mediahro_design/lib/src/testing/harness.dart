import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// English [KStrings] for tests of the design package. The app supplies the
/// localised implementation.
class KTestStrings extends KStrings {
  const KTestStrings();

  @override
  String get close => 'Close';
  @override
  String get back => 'Back';
  @override
  String get loading => 'Loading';
  @override
  String get managedByOrganisation => 'Managed by your organisation';
  @override
  String get seekBar => 'Seek';
  @override
  String seekValue(String position, String duration) =>
      '$position of $duration';
  @override
  String get seekForwardLarge => 'Forward 10 percent';
  @override
  String get seekBackLarge => 'Back 10 percent';
  @override
  String get compareDivider => 'Comparison divider';
  @override
  String compareItem(int index, int count) => 'Image $index of $count';
  @override
  String percent(int value) => '$value %';
  @override
  String get showAdvanced => 'Show advanced';
  @override
  String get hideAdvanced => 'Hide advanced';
  @override
  String get collapseSidebar => 'Collapse sidebar';
  @override
  String get expandSidebar => 'Expand sidebar';
}

/// Golden comparator. Goldens are recorded on Linux, the CI host
/// (re-record with `flutter test --update-goldens` on Linux or WSL). On
/// Linux the comparison is near-exact; other hosts render
/// text and anti-aliasing slightly differently, so local runs on Windows
/// and macOS allow a small fraction of differing pixels.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {double? tolerance})
    : tolerance = tolerance ?? (Platform.isLinux ? 0.0005 : 0.02);

  /// Fraction of differing pixels allowed.
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

/// Call from `flutter_test_config.dart`.
Future<void> runWithTolerantGoldens(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      Uri.parse('${current.basedir}golden_test.dart'),
    );
  }
  await testMain();
}

/// One rendering condition of the golden matrix (docs/11 §1: text scales,
/// RTL, reduced motion).
@immutable
final class KVariant {
  const KVariant(this.textScale, this.direction, {this.reduced = false});

  final double textScale;
  final TextDirection direction;

  /// Reduced motion and reduced transparency together.
  final bool reduced;

  @override
  String toString() =>
      '${textScale}x ${direction.name}${reduced ? ' reduced' : ''}';
}

/// 3 text scales × LTR/RTL, plus reduced motion + transparency.
const List<KVariant> kGoldenVariants = [
  KVariant(1, TextDirection.ltr),
  KVariant(1, TextDirection.rtl),
  KVariant(1.5, TextDirection.ltr),
  KVariant(1.5, TextDirection.rtl),
  KVariant(2, TextDirection.ltr),
  KVariant(2, TextDirection.rtl),
  KVariant(1, TextDirection.ltr, reduced: true),
];

ThemeData kTestTheme(
  PlatformFamily family,
  Brightness brightness, {
  MediaMode mode = MediaMode.video,
  bool highContrast = false,
}) => MediahroTheme.build(
  ThemeSpec(
    family: family,
    brightness: brightness,
    mode: mode,
    highContrast: highContrast,
  ),
);

/// Wraps [child] in everything a component needs for one [variant].
Widget kVariantScope({
  required ThemeData theme,
  required KVariant variant,
  required Widget child,
  KStrings strings = const KTestStrings(),
  KStrings Function(BuildContext context)? stringsBuilder,
  Size? size,
}) => Builder(
  builder: (context) => Theme(
    data: theme,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(variant.textScale),
        disableAnimations: variant.reduced,
        size: size,
      ),
      child: Directionality(
        textDirection: variant.direction,
        child: KAccessibility(
          data: KAccessibilityData(
            reduceMotion: variant.reduced,
            reduceTransparency: variant.reduced,
          ),
          child: KStringsScope(
            strings: stringsBuilder?.call(context) ?? strings,
            child: Material(
              color: theme.colorScheme.surface,
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// Pumps one component for behaviour and accessibility tests.
Future<void> pumpK(
  WidgetTester tester,
  Widget child, {
  PlatformFamily family = PlatformFamily.material,
  Brightness brightness = Brightness.light,
  KVariant variant = const KVariant(1, TextDirection.ltr),
  Size size = const Size(400, 800),
  MediaMode mode = MediaMode.video,
  bool settle = true,
  Iterable<LocalizationsDelegate<Object?>>? localizationsDelegates,
  Iterable<Locale> supportedLocales = const [Locale('en')],
  KStrings Function(BuildContext context)? stringsBuilder,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = kTestTheme(family, brightness, mode: mode);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      // Scopes sit above the navigator so sheets and dialogs see them too.
      builder: (context, navigator) => kVariantScope(
        theme: theme,
        variant: variant,
        stringsBuilder: stringsBuilder,
        child: navigator!,
      ),
      home: child,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Renders [builder] in every [kGoldenVariants] cell for one platform family
/// and brightness and compares with
/// `goldens/<family>/<name>_<brightness>.png`.
Future<void> expectGoldenMatrix(
  WidgetTester tester, {
  required String name,
  required PlatformFamily family,
  required Brightness brightness,
  required WidgetBuilder builder,
  double cellWidth = 360,
  int columns = 4,
  double cellHeight = 800,
  MediaMode mode = MediaMode.video,
  Iterable<LocalizationsDelegate<Object?>>? localizationsDelegates,
  Iterable<Locale> supportedLocales = const [Locale('en')],
  KStrings Function(BuildContext context)? stringsBuilder,
}) async {
  const gap = 8.0;
  tester.view
    ..physicalSize = Size(columns * (cellWidth + gap) + gap, 4000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = kTestTheme(family, brightness, mode: mode);
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF808080),
            child: Padding(
              padding: const EdgeInsets.all(gap),
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final v in kGoldenVariants)
                    SizedBox(
                      width: cellWidth,
                      child: kVariantScope(
                        theme: theme,
                        variant: v,
                        stringsBuilder: stringsBuilder,
                        // Window-class layouts see the cell as the window.
                        size: Size(cellWidth, cellHeight),
                        child: Builder(builder: builder),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(
    find.byKey(key),
    matchesGoldenFile('goldens/${family.name}/${name}_${brightness.name}.png'),
  );
}

/// Accessibility guidelines for one family (SYS-008): platform tap target
/// (48 dp Material, 44 pt Apple/Windows), labelled targets, text contrast.
Future<void> expectAccessible(
  WidgetTester tester,
  PlatformFamily family,
) async {
  await expectLater(
    tester,
    meetsGuideline(
      family == PlatformFamily.material
          ? androidTapTargetGuideline
          : iOSTapTargetGuideline,
    ),
  );
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}
