import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Window size classes (SYS-011), Material 3 breakpoints by width.
enum KWindowClass {
  /// Phones in portrait (< 600).
  compact(0),

  /// Large phones in landscape, small tablets, foldables unfolded (600–839).
  medium(600),

  /// Tablets, small desktop windows (840–1199).
  expanded(840),

  /// Desktop (1200–1599).
  large(1200),

  /// Wide desktop (≥ 1600).
  extraLarge(1600);

  const KWindowClass(this.minWidth);

  final double minWidth;

  static KWindowClass forWidth(double width) =>
      values.lastWhere((c) => width >= c.minWidth);

  static KWindowClass of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == compact;

  /// Sidebar / rail instead of a bottom bar.
  bool get usesSidebar => index >= medium.index;

  /// Show list and detail side by side.
  bool get showsListDetail => index >= expanded.index;

  /// Sidebar shows labels next to icons.
  bool get extendedSidebar => index >= large.index;

  /// Maximum grid density (docs/06 §3.3: up to 6 columns on phones, 12 on
  /// desktop).
  int get maxGridColumns => isCompact ? 6 : 12;
}

/// Fold posture from the platform's display features (SYS-011 tabletop).
enum KPosture { flat, tabletop, book }

KPosture postureOf(BuildContext context) {
  final features = MediaQuery.maybeDisplayFeaturesOf(context) ?? const [];
  for (final f in features) {
    if (f.type != DisplayFeatureType.fold &&
        f.type != DisplayFeatureType.hinge) {
      continue;
    }
    if (f.state != DisplayFeatureState.postureHalfOpened) continue;
    return f.bounds.width > f.bounds.height ? KPosture.tabletop : KPosture.book;
  }
  return KPosture.flat;
}

/// List-detail layout (SYS-011): side by side when the space it is given is
/// at least [KWindowClass.expanded] wide, otherwise only the list (the
/// caller pushes the detail as a route). Uses its own constraints, not the
/// window, so it also works inside panes and split views.
class KListDetail extends StatelessWidget {
  const KListDetail({
    required this.list,
    required this.detail,
    this.listWidth = 360,
    super.key,
  });

  final Widget list;

  /// Shown beside the list on wide windows; null when nothing is selected.
  final Widget? detail;
  final double listWidth;

  /// Whether a pane of [width] shows list and detail together.
  static bool sideBySide(double width) =>
      KWindowClass.forWidth(width).showsListDetail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!sideBySide(constraints.maxWidth)) return list;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: listWidth, child: list),
          const _Divider(),
          Expanded(child: detail ?? const SizedBox.shrink()),
        ],
      );
    },
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    color: DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.12),
  );
}

/// Tabletop posture (SYS-011): [top] above the fold (the player), [bottom]
/// below it (controls). Flat devices show [flat].
class KTabletopLayout extends StatelessWidget {
  const KTabletopLayout({
    required this.top,
    required this.bottom,
    required this.flat,
    super.key,
  });

  final Widget top;
  final Widget bottom;
  final Widget flat;

  @override
  Widget build(BuildContext context) {
    if (postureOf(context) != KPosture.tabletop) return flat;
    final fold = (MediaQuery.maybeDisplayFeaturesOf(context) ?? const [])
        .firstWhere(
          (f) =>
              f.type == DisplayFeatureType.fold ||
              f.type == DisplayFeatureType.hinge,
        );
    return Column(
      children: [
        SizedBox(height: fold.bounds.top, child: top),
        SizedBox(height: fold.bounds.height),
        Expanded(child: bottom),
      ],
    );
  }
}
