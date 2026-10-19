import 'dart:ui' show Brightness;

import 'package:flutter/animation.dart';

/// Spacing scale in logical pixels (docs/06 §4).
abstract final class KSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;

  static const List<double> scale = [s4, s8, s12, s16, s20, s24, s32, s40, s48];
}

abstract final class KRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Fully rounded ends.
  static const double pill = 999;
}

/// Elevation levels: 0 flat, 1 cards, 2 sheets, 3 dialogs.
abstract final class KElevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
}

abstract final class KMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);

  /// Spring stiffness 400, damping 30 (mass 1).
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 30,
  );

  /// Duration to use given the platform reduced-motion setting: with reduced
  /// motion only crossfades of [fast] length are allowed.
  static Duration resolve(Duration d, {required bool reduceMotion}) =>
      reduceMotion ? fast : d;
}

/// Minimum interactive target (44 × 44 pt, CLAUDE.md §1.8).
abstract final class KTarget {
  static const double min = 44;
}

/// Brand colours (docs/03 §3.3). Light value first, dark-theme value second.
abstract final class KBrand {
  static const Color primary = Color(0xFF3A5BFF);
  static const Color primaryDark = Color(0xFF7B93FF);
  static const Color secondary = Color(0xFFFF7A59);
  static const Color secondaryDark = Color(0xFFFF9A80);
  static const Color tertiary = Color(0xFF22C3A6);
  static const Color tertiaryDark = Color(0xFF5EDDC6);

  /// Video surface is always true black.
  static const Color playerSurface = Color(0xFF000000);

  /// Player chrome text: white at 92 %.
  static const Color onPlayer = Color(0xEBFFFFFF);

  /// Player chrome scrim: black at 60 %.
  static const Color playerScrim = Color(0x99000000);
  static const Color subtitleFill = Color(0xFFFFFFFF);
  static const Color subtitleOutline = Color(0xFF000000);
}

/// The three modes each carry their own accent (docs/03 §3.3).
enum MediaMode {
  video(KBrand.primary, KBrand.primaryDark),
  music(KBrand.secondary, KBrand.secondaryDark),
  photos(KBrand.tertiary, KBrand.tertiaryDark);

  const MediaMode(this.accentLight, this.accentDark);

  final Color accentLight;
  final Color accentDark;

  Color accent(Brightness b) => b == Brightness.dark ? accentDark : accentLight;
}

/// WCAG relative-luminance contrast ratio, used by token tests and the
/// high-contrast theme builder.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
