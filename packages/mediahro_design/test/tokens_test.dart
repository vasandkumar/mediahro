import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_design/mediahro_design.dart';

void main() {
  test('docs/06 §4 spacing scale', () {
    expect(KSpacing.scale, [4, 8, 12, 16, 20, 24, 32, 40, 48]);
  });

  test('docs/06 §4 motion tokens and reduced motion', () {
    expect(KMotion.fast.inMilliseconds, 120);
    expect(KMotion.base.inMilliseconds, 200);
    expect(KMotion.slow.inMilliseconds, 300);
    expect(KMotion.resolve(KMotion.slow, reduceMotion: true), KMotion.fast);
  });

  test('every icon resolves on every platform family', () {
    for (final f in PlatformFamily.values) {
      for (final i in KIcon.values) {
        expect(i.resolve(f), isA<IconData>());
      }
    }
  });

  group('CORE-007 themes', () {
    for (final family in PlatformFamily.values) {
      for (final b in Brightness.values) {
        for (final mode in MediaMode.values) {
          test(
            '${family.name}/${b.name}/${mode.name}: primary carries the mode accent hue at ≥ 4.5:1',
            () {
              final t = MediahroTheme.build(
                ThemeSpec(family: family, brightness: b, mode: mode),
              );
              expect(t.mediahro.accent, mode.accent(b));
              expect(
                HSLColor.fromColor(t.colorScheme.primary).hue,
                closeTo(HSLColor.fromColor(mode.accent(b)).hue, 2),
              );
              expect(
                contrastRatio(t.colorScheme.primary, t.colorScheme.surface),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrastRatio(t.colorScheme.onPrimary, t.colorScheme.primary),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrastRatio(t.colorScheme.onSurface, t.colorScheme.surface),
                greaterThanOrEqualTo(4.5),
              );
              expect(t.mediahro.playerSurface, const Color(0xFF000000));
            },
          );
        }
      }
    }

    test('AMOLED dark uses true black surfaces', () {
      final t = MediahroTheme.build(
        const ThemeSpec(
          family: PlatformFamily.material,
          brightness: Brightness.dark,
          amoled: true,
        ),
      );
      expect(t.colorScheme.surface, Colors.black);
    });

    test('user accent override replaces the mode accent', () {
      final t = MediahroTheme.build(
        const ThemeSpec(
          family: PlatformFamily.material,
          brightness: Brightness.light,
          accent: Color(0xFF8E24AA),
        ),
      );
      expect(t.mediahro.accent, const Color(0xFF8E24AA));
    });

    test(
      'platform materials: solid on Material, glass on Apple, Mica on Windows',
      () {
        KBarMaterial bar(PlatformFamily f) => MediahroTheme.build(
          ThemeSpec(family: f, brightness: Brightness.light),
        ).mediahroMaterials.bar;
        expect(bar(PlatformFamily.material), KBarMaterial.solid);
        expect(bar(PlatformFamily.apple), KBarMaterial.glass);
        expect(bar(PlatformFamily.fluent), KBarMaterial.mica);
      },
    );

    test('CORE-001 themes are cached so mode switches do not rebuild them', () {
      const spec = ThemeSpec(
        family: PlatformFamily.material,
        brightness: Brightness.dark,
        mode: MediaMode.music,
      );
      expect(
        identical(MediahroTheme.build(spec), MediahroTheme.build(spec)),
        isTrue,
      );
    });

    test('high contrast reaches 7:1 on surfaces', () {
      for (final b in Brightness.values) {
        final t = MediahroTheme.build(
          ThemeSpec(
            family: PlatformFamily.fluent,
            brightness: b,
            highContrast: true,
          ),
        );
        expect(
          contrastRatio(t.colorScheme.onSurface, t.colorScheme.surface),
          greaterThanOrEqualTo(7),
        );
        expect(
          contrastRatio(t.colorScheme.primary, t.colorScheme.surface),
          greaterThanOrEqualTo(7),
        );
      }
    });
  });
}
