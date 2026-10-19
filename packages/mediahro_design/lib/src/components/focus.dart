import 'package:flutter/material.dart';
import 'package:mediahro_design/src/theme.dart';

/// Draws a visible focus ring around custom controls when they hold
/// keyboard focus (docs/06 §7: "focus visible on all platforms").
class KFocusRing extends StatelessWidget {
  const KFocusRing({
    required this.focused,
    required this.child,
    this.radius,
    super.key,
  });

  final bool focused;
  final Widget child;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          radius ?? theme.mediahroShape.controlRadius.clamp(0, 24),
        ),
        border: focused && highlight
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: child,
    );
  }
}
