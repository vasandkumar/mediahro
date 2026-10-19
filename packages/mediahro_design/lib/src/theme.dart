import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
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
    required this.success,
    required this.playerSurface,
    required this.playerChrome,
    required this.playerScrim,
    required this.subtitleFill,
    required this.subtitleOutline,
  });

  final Color success;
  final Color playerSurface;
  final Color playerChrome;
  final Color playerScrim;
  final Color subtitleFill;
  final Color subtitleOutline;

  @override
  MediahroColors copyWith({
    Color? success,
    Color? playerSurface,
    Color? playerChrome,
    Color? playerScrim,
    Color? subtitleFill,
    Color? subtitleOutline,
  }) => MediahroColors(
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
  });

  final PlatformFamily family;
  final double cardRadius;
  final double controlRadius;

  @override
  MediahroShape copyWith({
    PlatformFamily? family,
    double? cardRadius,
    double? controlRadius,
  }) => MediahroShape(
    family: family ?? this.family,
    cardRadius: cardRadius ?? this.cardRadius,
    controlRadius: controlRadius ?? this.controlRadius,
  );

  @override
  MediahroShape lerp(MediahroShape? other, double t) =>
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
  });

  final PlatformFamily family;
  final Brightness brightness;
  final MediaMode mode;

  /// True-black surfaces in dark theme.
  final bool amoled;
  final bool highContrast;

  /// Material You scheme from the platform (Android, opt-in).
  final ColorScheme? dynamicScheme;
}

/// Builds the [ThemeData] for a platform family (docs/06 §4–5). Platform
/// materials (Liquid Glass, Mica) are applied by the shell, never over video.
abstract final class MediahroTheme {
  static ThemeData build(ThemeSpec spec) {
    final dark = spec.brightness == Brightness.dark;
    final accent = spec.mode.accent(spec.brightness);
    var scheme =
        spec.dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: spec.brightness,
          contrastLevel: spec.highContrast ? 1 : 0,
        ).copyWith(primary: accent, onPrimary: _onColor(accent));
    if (spec.amoled && dark) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
      );
    }
    if (spec.highContrast) {
      scheme = scheme.copyWith(
        surface: dark ? Colors.black : Colors.white,
        onSurface: dark ? Colors.white : Colors.black,
        outline: dark ? Colors.white : Colors.black,
      );
    }

    final (cardRadius, controlRadius) = switch (spec.family) {
      PlatformFamily.material => (KRadius.lg, KRadius.pill),
      PlatformFamily.apple => (KRadius.md, KRadius.sm),
      PlatformFamily.fluent => (KRadius.sm, KRadius.xs),
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
      visualDensity: spec.family == PlatformFamily.material
          ? VisualDensity.standard
          : VisualDensity.compact,
      scaffoldBackgroundColor: scheme.surface,
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
        ),
      ],
    );
  }

  static Color _onColor(Color c) =>
      contrastRatio(c, Colors.white) >= contrastRatio(c, Colors.black)
      ? Colors.white
      : Colors.black;
}

extension MediahroThemeX on ThemeData {
  MediahroColors get mediahro => extension<MediahroColors>()!;
  MediahroShape get mediahroShape => extension<MediahroShape>()!;
}
