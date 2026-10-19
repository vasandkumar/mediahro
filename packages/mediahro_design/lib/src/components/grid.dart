import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/foundation/adaptive.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

/// Columns for a grid of [width] given either an explicit density or a
/// minimum tile width, capped per window class (docs/06 §3.3: 1–6 on
/// phones, up to 12 on desktop).
int kGridColumns({
  required double width,
  int? columns,
  double minTileWidth = 140,
}) {
  final cap = KWindowClass.forWidth(width).maxGridColumns;
  final n = columns ?? (width / minTileWidth).floor();
  return math.max(1, math.min(cap, n));
}

/// Adaptive media grid (docs/06 §10): albums, posters, the photo timeline.
/// Keyboard focus moves in reading order (mirrored in RTL).
class KGrid extends StatelessWidget {
  const KGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.columns,
    this.minTileWidth = 140,
    this.childAspectRatio = 1,
    this.spacing = KSpacing.s8,
    this.padding = const EdgeInsets.all(KSpacing.s8),
    this.controller,
    this.footerHeight = 0,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Explicit density (pinch-to-change on the photo timeline).
  final int? columns;
  final double minTileWidth;

  /// Aspect ratio of the artwork area.
  final double childAspectRatio;
  final double spacing;
  final EdgeInsets padding;
  final ScrollController? controller;

  /// Height of a caption under each tile at text scale 1 (scaled with the
  /// user's text size so captions are never clipped).
  final double footerHeight;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final n = kGridColumns(
          width: width,
          columns: columns,
          minTileWidth: minTileWidth,
        );
        final tileWidth = (width - spacing * (n - 1)) / n;
        final extent =
            tileWidth / childAspectRatio + scaler.scale(footerHeight);
        return FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: GridView.builder(
            controller: controller,
            padding: padding,
            itemCount: itemCount,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: n,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              mainAxisExtent: extent,
            ),
            itemBuilder: itemBuilder,
          ),
        );
      },
    );
  }
}

/// One grid tile: artwork plus an optional caption and badges (RAW, Live,
/// HDR, a video duration). Selection shows a check mark, not colour alone.
class KGridTile extends StatefulWidget {
  const KGridTile({
    required this.semanticLabel,
    required this.artwork,
    this.title,
    this.subtitle,
    this.badges = const [],
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  /// Spoken label (e.g. the album name and artist, or photo date).
  final String semanticLabel;
  final Widget artwork;
  final String? title;
  final String? subtitle;
  final List<String> badges;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<KGridTile> createState() => _KGridTileState();
}

class _KGridTileState extends State<KGridTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(
      theme.mediahroShape.cardRadius.clamp(0, 12),
    );
    final reduceMotion = KAccessibility.reduceMotion(context);
    final art = ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: widget.artwork,
          ),
          if (widget.badges.isNotEmpty)
            PositionedDirectional(
              bottom: KSpacing.s4,
              end: KSpacing.s4,
              child: Wrap(
                spacing: KSpacing.s4,
                children: [
                  for (final b in widget.badges)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(KRadius.xs),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KSpacing.s4,
                          vertical: 2,
                        ),
                        child: Text(
                          b,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.selectionMode)
            PositionedDirectional(
              top: KSpacing.s4,
              start: KSpacing.s4,
              child: Icon(
                widget.selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: widget.selected ? scheme.primary : Colors.white,
                shadows: const [Shadow(blurRadius: 4)],
              ),
            ),
          if (widget.selected)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: scheme.primary, width: 3),
              ),
            ),
          if (_focused)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: scheme.onSurface, width: 2),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      selected: widget.selectionMode ? widget.selected : null,
      excludeSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onFocusChange: (v) => setState(() => _focused = v),
        borderRadius: radius,
        splashFactory: reduceMotion ? NoSplash.splashFactory : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: art),
            if (widget.title != null)
              Padding(
                padding: const EdgeInsets.only(top: KSpacing.s4),
                child: Text(
                  widget.title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
