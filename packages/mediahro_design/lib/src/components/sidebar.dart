import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/foundation/materials.dart';
import 'package:mediahro_design/src/icons.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

@immutable
final class KSidebarItem {
  const KSidebarItem({
    required this.icon,
    required this.label,
    this.dividerBefore = false,
    this.key,
  });

  final KIcon icon;
  final String label;

  /// Key of the destination's tile, for tests and automation.
  final Key? key;

  /// Starts a new group (e.g. Sources and Settings below the three modes).
  final bool dividerBefore;
}

/// Primary navigation on tablets and desktop (docs/06 §2, SYS-011): a
/// Material 3 navigation rail on Android (icon in an indicator pill, label
/// below), a source-list sidebar on Apple platforms, a NavigationView pane
/// with a selection bar on Windows.
///
/// [extended] shows labels beside icons. Collapsed Apple/Windows items keep
/// their label as tooltip and accessibility label. Above 130 % text the
/// sidebar always extends so labels reflow instead of truncating (SYS-008).
class KSidebar extends StatelessWidget {
  const KSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.extended = false,
    this.header,
    super.key,
  });

  final List<KSidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final ext = extended || scale > 1.3;
    final material = theme.mediahroShape.family == PlatformFamily.material;
    final width = ext
        ? (240 + (scale - 1) * 80).clamp(240.0, 320.0)
        : (material ? 80.0 : 72.0);
    return SizedBox(
      width: width,
      child: KBarSurface(
        child: SafeArea(
          right: false,
          left: false,
          child: FocusTraversalGroup(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: KSpacing.s8),
              children: [
                ?header,
                for (final (i, item) in items.indexed) ...[
                  if (item.dividerBefore)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: KSpacing.s8,
                        horizontal: KSpacing.s12,
                      ),
                      child: Divider(height: 1),
                    ),
                  if (!ext && material)
                    _RailTile(
                      key: item.key,
                      item: item,
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    )
                  else
                    _SidebarTile(
                      key: item.key,
                      item: item,
                      selected: i == selectedIndex,
                      extended: ext,
                      onTap: () => onSelected(i),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Material 3 rail destination: indicator pill around the icon, label below.
class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.item,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final KSidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = KAccessibility.reduceMotion(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        splashFactory: reduceMotion ? NoSplash.splashFactory : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KSpacing.s4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: KMotion.resolve(
                    KMotion.base,
                    reduceMotion: reduceMotion,
                  ),
                  width: 56,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(KRadius.pill),
                  ),
                  child: Icon(
                    item.icon.resolve(PlatformFamily.material),
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: KSpacing.s4),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
    super.key,
  });

  final KSidebarItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = theme.mediahroShape;
    final fluent = shape.family == PlatformFamily.fluent;
    final reduceMotion = KAccessibility.reduceMotion(context);
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    final radius = BorderRadius.circular(shape.controlRadius.clamp(4, 10));

    final content = Row(
      mainAxisAlignment: extended
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        if (fluent)
          AnimatedContainer(
            duration: KMotion.resolve(KMotion.fast, reduceMotion: reduceMotion),
            width: 3,
            height: selected ? 16 : 0,
            margin: const EdgeInsetsDirectional.only(end: KSpacing.s4),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Icon(item.icon.resolve(shape.family), color: fg),
        if (extended) ...[
          const SizedBox(width: KSpacing.s12),
          Expanded(
            child: Text(
              item.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ],
    );

    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.s4, vertical: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          splashFactory: reduceMotion ? NoSplash.splashFactory : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: shape.minTarget,
              minWidth: shape.minTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KSpacing.s8,
                vertical: KSpacing.s8,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      selected: selected,
      button: true,
      label: extended ? null : item.label,
      child: extended
          ? tile
          : Tooltip(
              message: item.label,
              excludeFromSemantics: true,
              child: tile,
            ),
    );
  }
}
