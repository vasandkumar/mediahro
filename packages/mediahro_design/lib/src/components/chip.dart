import 'package:flutter/material.dart';
import 'package:mediahro_design/src/icons.dart';
import 'package:mediahro_design/src/theme.dart';

/// Filter / choice chip (docs/06 §10): source filter, speed, subtitle and
/// audio chips. Selection shows a check mark as well as the fill, and the
/// tap target is padded to the platform minimum.
class KChip extends StatelessWidget {
  const KChip({
    required this.label,
    this.selected = false,
    this.onSelected,
    this.onPressed,
    this.icon,
    this.semanticLabel,
    this.onDark = false,
    super.key,
  }) : assert(
         onSelected == null || onPressed == null,
         'A chip either toggles (onSelected) or acts (onPressed).',
       );

  final String label;
  final bool selected;

  /// Toggle chip.
  final ValueChanged<bool>? onSelected;

  /// Action chip (opens a sheet, e.g. "Subtitles: English").
  final VoidCallback? onPressed;
  final KIcon? icon;

  /// Full spoken label when [label] is abbreviated ("1.5×" → "Speed 1.5×").
  final String? semanticLabel;

  /// White-on-scrim styling for the player chrome.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final family = theme.mediahroShape.family;
    final radius = BorderRadius.circular(
      family == PlatformFamily.material ? 8 : theme.mediahroShape.controlRadius,
    );
    final fg = onDark ? Colors.white : null;
    final avatar = icon == null
        ? null
        : Icon(icon!.resolve(family), size: 18, color: fg);
    final text = Text(label, style: fg == null ? null : TextStyle(color: fg));
    final side = onDark ? const BorderSide(color: Colors.white70) : null;
    final shape = RoundedRectangleBorder(borderRadius: radius);

    final Widget chip = onPressed != null
        ? ActionChip(
            label: text,
            avatar: avatar,
            onPressed: onPressed,
            side: side,
            shape: shape,
            backgroundColor: onDark ? Colors.black54 : null,
            materialTapTargetSize: MaterialTapTargetSize.padded,
          )
        : FilterChip(
            label: text,
            avatar: selected ? null : avatar,
            selected: selected,
            onSelected: onSelected,
            side: side,
            shape: shape,
            checkmarkColor: fg,
            backgroundColor: onDark ? Colors.black54 : null,
            selectedColor: onDark ? Colors.white24 : null,
            materialTapTargetSize: MaterialTapTargetSize.padded,
          );
    if (semanticLabel == null) return chip;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      button: true,
      selected: onSelected != null ? selected : null,
      onTap:
          onPressed ??
          (onSelected == null ? null : () => onSelected!(!selected)),
      child: chip,
    );
  }
}
