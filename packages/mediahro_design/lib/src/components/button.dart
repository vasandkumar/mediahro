import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/icons.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

enum KButtonVariant {
  /// The one most likely action on a screen (filled, accent).
  primary,

  /// Other actions (outlined).
  secondary,

  /// Low-emphasis actions such as "Not now" (text only).
  tertiary,
}

/// Labelled button (docs/06 §10). Meets the platform target size, wraps its
/// label at large text sizes instead of truncating it, and drops the ripple
/// when reduced motion is on.
class KButton extends StatelessWidget {
  const KButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = KButtonVariant.secondary,
    this.expand = false,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final KIcon? icon;
  final KButtonVariant variant;

  /// Stretch to the available width.
  final bool expand;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = theme.mediahroShape;
    final reduceMotion = KAccessibility.reduceMotion(context);
    final min = shape.minTarget;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        expand ? Size(double.infinity, min) : Size(min, min),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: KSpacing.s16, vertical: KSpacing.s8),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.controlRadius),
        ),
      ),
      splashFactory: reduceMotion ? NoSplash.splashFactory : null,
      animationDuration: reduceMotion ? Duration.zero : null,
    );
    final text = Text(label, textAlign: TextAlign.center, softWrap: true);
    final iconWidget = icon == null
        ? null
        : Icon(icon!.resolve(shape.family), size: 20);

    return switch (variant) {
      KButtonVariant.primary =>
        iconWidget == null
            ? FilledButton(
                onPressed: onPressed,
                style: style,
                focusNode: focusNode,
                autofocus: autofocus,
                child: text,
              )
            : FilledButton.icon(
                onPressed: onPressed,
                style: style,
                focusNode: focusNode,
                autofocus: autofocus,
                icon: iconWidget,
                label: text,
              ),
      KButtonVariant.secondary =>
        iconWidget == null
            ? OutlinedButton(
                onPressed: onPressed,
                style: style,
                focusNode: focusNode,
                autofocus: autofocus,
                child: text,
              )
            : OutlinedButton.icon(
                onPressed: onPressed,
                style: style,
                focusNode: focusNode,
                autofocus: autofocus,
                icon: iconWidget,
                label: text,
              ),
      KButtonVariant.tertiary =>
        iconWidget == null
            ? TextButton(
                onPressed: onPressed,
                style: style,
                focusNode: focusNode,
                autofocus: autofocus,
                child: text,
              )
            : TextButton.icon(
                onPressed: onPressed,
                style: style,
                focusNode: focusNode,
                autofocus: autofocus,
                icon: iconWidget,
                label: text,
              ),
    };
  }
}

/// Icon-only button. [label] is required: it is the accessibility label and
/// the tooltip (docs/06 §7). Toggle buttons pass [selected] so the state is
/// announced and drawn with a filled background, not colour alone.
class KIconButton extends StatelessWidget {
  const KIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected,
    this.selectedIcon,
    this.color,
    this.size = 24,
    this.focusNode,
    super.key,
  });

  final KIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool? selected;
  final KIcon? selectedIcon;

  /// Foreground override, e.g. white on the player chrome.
  final Color? color;
  final double size;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final family = theme.mediahroShape.family;
    final min = theme.mediahroShape.minTarget;
    final reduceMotion = KAccessibility.reduceMotion(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      isSelected: selected,
      focusNode: focusNode,
      color: color,
      iconSize: size,
      constraints: BoxConstraints(minWidth: min, minHeight: min),
      style: ButtonStyle(
        splashFactory: reduceMotion ? NoSplash.splashFactory : null,
        backgroundColor: selected ?? false
            ? WidgetStatePropertyAll(
                (color ?? theme.colorScheme.primary).withValues(alpha: 0.16),
              )
            : null,
      ),
      icon: Icon(icon.resolve(family)),
      selectedIcon: selectedIcon == null
          ? null
          : Icon(selectedIcon!.resolve(family)),
    );
  }
}
