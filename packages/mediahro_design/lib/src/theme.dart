import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/materials.dart';
import 'package:mediahro_design/src/tokens.dart';

/// Platform families with their own visual language (docs/06 §5).
enum PlatformFamily { material, apple, fluent }

PlatformFamily platformFamilyFor(TargetPlatform p) => switch (p) {
  TargetPlatform.iOS || TargetPlatform.macOS => PlatformFamily.apple,
  TargetPlatform.windows => PlatformFamily.fluent,
  _ => PlatformFamily.material,
};

/// Colour roles beyond [ColorScheme] (docs/06 §4).
@immutable
final class MediahroColors extends ThemeExtension<MediahroColors> {
  const MediahroColors({
    required this.accent,
    required this.success,
    required this.playerSurface,
    required this.playerChrome,
    required this.playerScrim,
    required this.subtitleFill,
    required this.subtitleOutline,
  });

  /// The exact brand accent of the current mode, for decorative fills only.
  /// Text and indicators use [ColorScheme.primary]: the same hue adjusted to
  /// meet contrast on the current surface.
  final Color accent;
  final Color success;
  final Color playerSurface;
  final Color playerChrome;
  final Color playerScrim;
  final Color subtitleFill;
  final Color subtitleOutline;

  @override
  MediahroColors copyWith({
    Color? accent,
    Color? success,
    Color? playerSurface,
    Color? playerChrome,
    Color? playerScrim,
    Color? subtitleFill,
    Color? subtitleOutline,
  }) => MediahroColors(
    accent: accent ?? this.accent,
    success: success ?? this.success,
    playerSurface: playerSurface ?? this.playerSurface,
    playerChrome: playerChrome ?? this.playerChrome,
    playerScrim: playerScrim ?? this.playerScrim,
    subtitleFill: subtitleFill ?? this.subtitleFill,
    subtitleOutline: subtitleOutline ?? this.subtitleOutline,
  );

  @override
  MediahroColors lerp(MediahroColors? other, double t) {
    if (other == null) return this;
    return MediahroColors(
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      playerSurface: Color.lerp(playerSurface, other.playerSurface, t)!,
      playerChrome: Color.lerp(playerChrome, other.playerChrome, t)!,
      playerScrim: Color.lerp(playerScrim, other.playerScrim, t)!,
      subtitleFill: Color.lerp(subtitleFill, other.subtitleFill, t)!,
      subtitleOutline: Color.lerp(subtitleOutline, other.subtitleOutline, t)!,
    );
  }
}

/// Shape and density tokens resolved per platform family.
@immutable
final class MediahroShape extends ThemeExtension<MediahroShape> {
  const MediahroShape({
    required this.family,
    required this.cardRadius,
    required this.controlRadius,
    required this.minTarget,
  });

  final PlatformFamily family;
  final double cardRadius;
  final double controlRadius;

  /// Minimum interactive size: 48 dp on Material (Android guideline), 44 pt
  /// on Apple and Windows (CLAUDE.md §1.8).
  final double minTarget;

  @override
  MediahroShape copyWith({
    PlatformFamily? family,
    double? cardRadius,
    double? controlRadius,
    double? minTarget,
  }) => MediahroShape(
    family: family ?? this.family,
    cardRadius: cardRadius ?? this.cardRadius,
    controlRadius: controlRadius ?? this.controlRadius,
    minTarget: minTarget ?? this.minTarget,
  );

  @override
  MediahroShape lerp(MediahroShape? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Platform material parameters for bars, sidebars and sheets (CORE-007).
@immutable
final class MediahroMaterials extends ThemeExtension<MediahroMaterials> {
  const MediahroMaterials({
    required this.bar,
    this.glassBlur = 24,
    this.glassOpacity = 0.72,
    this.micaTint = 0,
    this.micaActive = false,
  });

  final KBarMaterial bar;
  final double glassBlur;
  final double glassOpacity;

  /// Surface tint painted over Mica (0 = pure Mica).
  final double micaTint;

  /// Whether the Windows runner applied the Mica backdrop to the window.
  final bool micaActive;

  @override
  MediahroMaterials copyWith({
    KBarMaterial? bar,
    double? glassBlur,
    double? glassOpacity,
    double? micaTint,
    bool? micaActive,
  }) => MediahroMaterials(
    bar: bar ?? this.bar,
    glassBlur: glassBlur ?? this.glassBlur,
    glassOpacity: glassOpacity ?? this.glassOpacity,
    micaTint: micaTint ?? this.micaTint,
    micaActive: micaActive ?? this.micaActive,
  );

  @override
  MediahroMaterials lerp(MediahroMaterials? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Inputs to [MediahroTheme.build] (CORE-007).
@immutable
final class ThemeSpec {
  const ThemeSpec({
    required this.family,
    required this.brightness,
    this.mode = MediaMode.video,
    this.amoled = false,
    this.highContrast = false,
    this.dynamicScheme,
    this.accent,
    this.micaActive = false,
  });

  final PlatformFamily family;
  final Brightness brightness;
  final MediaMode mode;

  /// True-black surfaces in dark theme.
  final bool amoled;
  final bool highContrast;

  /// Material You scheme from the platform (Android, opt-in).
  final ColorScheme? dynamicScheme;

  /// User-chosen accent for [mode]; null uses the mode's brand accent.
  final Color? accent;

  /// The Windows runner applied Mica to the window (see [KBarMaterial.mica]).
  final bool micaActive;

  ThemeSpec copyWith({
    PlatformFamily? family,
    Brightness? brightness,
    MediaMode? mode,
    bool? amoled,
    bool? highContrast,
    ColorScheme? dynamicScheme,
    Color? accent,
    bool? micaActive,
  }) => ThemeSpec(
    family: family ?? this.family,
    brightness: brightness ?? this.brightness,
    mode: mode ?? this.mode,
    amoled: amoled ?? this.amoled,
    highContrast: highContrast ?? this.highContrast,
    dynamicScheme: dynamicScheme ?? this.dynamicScheme,
    accent: accent ?? this.accent,
    micaActive: micaActive ?? this.micaActive,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeSpec &&
      other.family == family &&
      other.brightness == brightness &&
      other.mode == mode &&
      other.amoled == amoled &&
      other.highContrast == highContrast &&
      other.dynamicScheme == dynamicScheme &&
      other.accent == accent &&
      other.micaActive == micaActive;

  @override
  int get hashCode => Object.hash(
    family,
    brightness,
    mode,
    amoled,
    highContrast,
    dynamicScheme,
    accent,
    micaActive,
  );
}

/// Builds the [ThemeData] for a platform family (docs/06 §4–5). Platform
/// materials (Liquid Glass, Mica) are painted by [KBarSurface] on bars,
/// sidebars and sheets, never over video.
abstract final class MediahroTheme {
  static final Map<ThemeSpec, ThemeData> _cache = {};

  /// Themes are cached: mode switches rebuild with an already-built theme so
  /// the switch stays within the 100 ms budget (CORE-001).
  static ThemeData build(ThemeSpec spec) => _cache[spec] ??= _build(spec);

  static ThemeData _build(ThemeSpec spec) {
    final dark = spec.brightness == Brightness.dark;
    final brand = spec.accent ?? spec.mode.accent(spec.brightness);
    var scheme = spec.dynamicScheme;
    if (scheme == null) {
      final seeded = ColorScheme.fromSeed(
        seedColor: brand,
        brightness: spec.brightness,
        contrastLevel: spec.highContrast ? 1 : 0,
      );
      final surface = dark
          ? (spec.amoled || spec.highContrast ? Colors.black : seeded.surface)
          : (spec.highContrast ? Colors.white : seeded.surface);
      final primary = accessibleAccent(
        brand,
        surface,
        minContrast: spec.highContrast ? 7 : 4.5,
      );
      scheme = seeded.copyWith(primary: primary, onPrimary: _onColor(primary));
    }
    if (spec.amoled && dark) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
      );
    }
    if (spec.highContrast) {
      scheme = scheme.copyWith(
        surface: dark ? Colors.black : Colors.white,
        onSurface: dark ? Colors.white : Colors.black,
        onSurfaceVariant: dark ? Colors.white : Colors.black,
        outline: dark ? Colors.white : Colors.black,
        outlineVariant: dark ? Colors.white70 : Colors.black87,
      );
    }

    final (cardRadius, controlRadius) = switch (spec.family) {
      PlatformFamily.material => (KRadius.lg, KRadius.pill),
      PlatformFamily.apple => (KRadius.md, KRadius.sm),
      PlatformFamily.fluent => (KRadius.sm, KRadius.xs),
    };
    final minTarget = spec.family == PlatformFamily.material
        ? KTarget.material
        : KTarget.min;
    final bar = switch (spec.family) {
      PlatformFamily.material => KBarMaterial.solid,
      PlatformFamily.apple => KBarMaterial.glass,
      PlatformFamily.fluent => KBarMaterial.mica,
    };

    final platform = switch (spec.family) {
      PlatformFamily.material => TargetPlatform.android,
      PlatformFamily.apple => TargetPlatform.iOS,
      PlatformFamily.fluent => TargetPlatform.windows,
    };

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: spec.brightness,
      platform: platform,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // Standard density everywhere: compact density shrinks controls below
      // the 44 pt minimum target (CLAUDE.md §1.8).
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      focusColor: scheme.primary.withValues(alpha: 0.24),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: Size.square(minTarget)),
      ),
      cardTheme: CardThemeData(
        elevation: KElevation.level1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      extensions: [
        MediahroColors(
          accent: brand,
          success: dark ? const Color(0xFF6DD58C) : const Color(0xFF146C2E),
          playerSurface: KBrand.playerSurface,
          playerChrome: KBrand.onPlayer,
          playerScrim: KBrand.playerScrim,
          subtitleFill: KBrand.subtitleFill,
          subtitleOutline: KBrand.subtitleOutline,
        ),
        MediahroShape(
          family: spec.family,
          cardRadius: cardRadius,
          controlRadius: controlRadius,
          minTarget: minTarget,
        ),
        MediahroMaterials(bar: bar, micaActive: spec.micaActive),
      ],
    );
  }

  static Color _onColor(Color c) =>
      contrastRatio(c, Colors.white) >= contrastRatio(c, Colors.black)
      ? Colors.white
      : Colors.black;
}

/// The same hue as [accent], darkened (light surfaces) or lightened (dark
/// surfaces) until it reaches [minContrast] against [surface].
Color accessibleAccent(
  Color accent,
  Color surface, {
  double minContrast = 4.5,
}) {
  if (contrastRatio(accent, surface) >= minContrast) return accent;
  final darken = surface.computeLuminance() > 0.5;
  var hsl = HSLColor.fromColor(accent);
  for (var i = 0; i < 100; i++) {
    final l = (hsl.lightness + (darken ? -0.01 : 0.01)).clamp(0.0, 1.0);
    hsl = hsl.withLightness(l);
    final c = hsl.toColor();
    if (contrastRatio(c, surface) >= minContrast) return c;
  }
  return darken ? Colors.black : Colors.white;
}

extension MediahroThemeX on ThemeData {
  MediahroColors get mediahro => extension<MediahroColors>()!;
  MediahroShape get mediahroShape => extension<MediahroShape>()!;
  MediahroMaterials get mediahroMaterials => extension<MediahroMaterials>()!;
  PlatformFamily get family => mediahroShape.family;
}
