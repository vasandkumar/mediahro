import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

/// List row (docs/06 §10): one tap plays or opens. The title never
/// truncates (it wraps at large text sizes); secondary text may.
///
/// An offline source's rows pass [unavailableLabel] ("Unavailable — last seen
/// 2 h ago", docs/06 §9): the row dims and shows the label, so state is never
/// carried by colour alone. Cached items stay tappable.
class KRow extends StatelessWidget {
  const KRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.unavailableLabel,
    this.semanticLabel,
    this.dense = false,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Artwork or icon, laid out in a 40 × 40 box.
  final Widget? leading;

  /// Duration, size or a control. Controls must carry their own label.
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;
  final String? unavailableLabel;

  /// Replaces the spoken label (defaults to title, subtitle and status).
  final String? semanticLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minTarget = theme.mediahroShape.minTarget;
    final dimmed = unavailableLabel != null || !enabled;
    final reduceMotion = KAccessibility.reduceMotion(context);

    final secondaryStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final content = Row(
      children: [
        if (leading != null) ...[
          SizedBox.square(dimension: 40, child: Center(child: leading)),
          const SizedBox(width: KSpacing.s16),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KSpacing.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: secondaryStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (unavailableLabel != null)
                  Text(unavailableLabel!, style: secondaryStyle),
              ],
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(width: KSpacing.s8),
          Icon(Icons.check_rounded, color: scheme.primary),
        ],
        if (trailing != null) ...[
          const SizedBox(width: KSpacing.s12),
          DefaultTextStyle.merge(style: secondaryStyle, child: trailing!),
        ],
      ],
    );

    final row = InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      splashFactory: reduceMotion ? NoSplash.splashFactory : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: dense ? minTarget : 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
          child: Opacity(opacity: dimmed ? 0.6 : 1, child: content),
        ),
      ),
    );

    return Semantics(
      selected: selected,
      enabled: enabled,
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: MergeSemantics(
        child: Material(
          type: MaterialType.transparency,
          color: selected ? scheme.secondaryContainer : null,
          child: Ink(
            color: selected ? scheme.primary.withValues(alpha: 0.08) : null,
            child: row,
          ),
        ),
      ),
    );
  }
}
