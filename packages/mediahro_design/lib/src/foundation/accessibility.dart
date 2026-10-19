import 'package:flutter/widgets.dart';

/// Accessibility preferences beyond [MediaQueryData] (docs/06 §7, SYS-008).
///
/// Reduced motion and high contrast are also read from the platform through
/// [MediaQuery]; reduced transparency has no Flutter equivalent, so the app
/// feeds it from the platform facade and the user's Appearance settings.
@immutable
final class KAccessibilityData {
  const KAccessibilityData({
    this.reduceMotion = false,
    this.reduceTransparency = false,
    this.highContrast = false,
  });

  /// User override on top of the platform setting.
  final bool reduceMotion;
  final bool reduceTransparency;
  final bool highContrast;

  @override
  bool operator ==(Object other) =>
      other is KAccessibilityData &&
      other.reduceMotion == reduceMotion &&
      other.reduceTransparency == reduceTransparency &&
      other.highContrast == highContrast;

  @override
  int get hashCode =>
      Object.hash(reduceMotion, reduceTransparency, highContrast);
}

class KAccessibility extends InheritedWidget {
  const KAccessibility({required this.data, required super.child, super.key});

  final KAccessibilityData data;

  static KAccessibilityData _data(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KAccessibility>()?.data ??
      const KAccessibilityData();

  /// Crossfades only, no parallax, no autoplaying previews.
  static bool reduceMotion(BuildContext context) =>
      _data(context).reduceMotion ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// Opaque chrome, sheets and bars.
  static bool reduceTransparency(BuildContext context) =>
      _data(context).reduceTransparency ||
      (MediaQuery.maybeHighContrastOf(context) ?? false);

  static bool highContrast(BuildContext context) =>
      _data(context).highContrast ||
      (MediaQuery.maybeHighContrastOf(context) ?? false);

  /// A screen reader or switch control is driving the UI: chrome must not
  /// auto-hide and gestures need button alternatives.
  static bool assistiveNavigation(BuildContext context) =>
      MediaQuery.maybeAccessibleNavigationOf(context) ?? false;

  @override
  bool updateShouldNotify(KAccessibility oldWidget) => data != oldWidget.data;
}
