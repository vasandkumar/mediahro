import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/theme.dart';

/// Platform materials for bars, sidebars and sheets (docs/06 §5, CORE-007).
enum KBarMaterial {
  /// Opaque surface (Material 3; any platform with reduced transparency).
  solid,

  /// Liquid-Glass-styled translucency with background blur (Apple). Never
  /// used over video: the player chrome uses scrims instead.
  glass,

  /// Transparent so the window's Mica backdrop shows through (Windows). Falls
  /// back to [solid] until the runner reports Mica is active.
  mica,
}

/// Paints a bar, sidebar or sheet background in the platform material of the
/// current theme. Opaque whenever reduced transparency is on.
class KBarSurface extends StatelessWidget {
  const KBarSurface({
    required this.child,
    this.elevated = false,
    this.borderRadius,
    super.key,
  });

  final Widget child;

  /// Sheets and dialogs use the higher surface container.
  final bool elevated;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final materials = theme.mediahroMaterials;
    final scheme = theme.colorScheme;
    final base = elevated
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainer;
    var material = materials.bar;
    if (KAccessibility.reduceTransparency(context)) {
      material = KBarMaterial.solid;
    }
    if (material == KBarMaterial.mica && !materials.micaActive) {
      material = KBarMaterial.solid;
    }

    Widget surface = switch (material) {
      KBarMaterial.solid => ColoredBox(color: base, child: child),
      KBarMaterial.mica => ColoredBox(
        color: base.withValues(alpha: materials.micaTint),
        child: child,
      ),
      KBarMaterial.glass => BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: materials.glassBlur,
          sigmaY: materials.glassBlur,
        ),
        child: ColoredBox(
          color: base.withValues(alpha: materials.glassOpacity),
          child: child,
        ),
      ),
    };
    if (borderRadius != null || material == KBarMaterial.glass) {
      surface = ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: surface,
      );
    }
    return surface;
  }
}
