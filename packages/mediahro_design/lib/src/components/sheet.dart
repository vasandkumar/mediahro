import 'package:flutter/material.dart';
import 'package:mediahro_design/src/components/button.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/foundation/adaptive.dart';
import 'package:mediahro_design/src/foundation/materials.dart';
import 'package:mediahro_design/src/foundation/strings.dart';
import 'package:mediahro_design/src/icons.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

enum KSheetPlacement {
  /// Bottom sheet on compact windows, side sheet from expanded up.
  adaptive,
  bottom,

  /// Side sheet on the trailing edge (player sheets on tablets/desktop).
  side,
}

/// Sheet surface with a title header and close button (docs/06 §3.1 side
/// sheets, §3.2 queue). Use [KSheet.show] to present one.
class KSheet extends StatelessWidget {
  const KSheet({
    required this.title,
    required this.child,
    this.actions = const [],
    this.onClose,
    this.scrollable = true,
    super.key,
  });

  final String title;
  final Widget child;

  /// Extra header actions (icon buttons).
  final List<Widget> actions;

  /// Defaults to popping the route.
  final VoidCallback? onClose;
  final bool scrollable;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    List<Widget> actions = const [],
    KSheetPlacement placement = KSheetPlacement.adaptive,
  }) {
    final side = switch (placement) {
      KSheetPlacement.side => true,
      KSheetPlacement.bottom => false,
      KSheetPlacement.adaptive => KWindowClass.of(context).showsListDetail,
    };
    final reduceMotion = KAccessibility.reduceMotion(context);
    final strings = KStrings.of(context);
    Widget sheet(BuildContext c) =>
        KSheet(title: title, actions: actions, child: builder(c));

    if (!side) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        sheetAnimationStyle: reduceMotion
            ? const AnimationStyle(
                duration: KMotion.fast,
                reverseDuration: KMotion.fast,
              )
            : null,
        builder: (c) => KBarSurface(
          elevated: true,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(
              Theme.of(c).mediahroShape.family == PlatformFamily.fluent
                  ? KRadius.sm
                  : KRadius.xl,
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(c).height * 0.9,
            ),
            child: sheet(c),
          ),
        ),
      );
    }

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: strings.close,
      barrierColor: Colors.black38,
      transitionDuration: KMotion.resolve(
        KMotion.slow,
        reduceMotion: reduceMotion,
      ),
      pageBuilder: (c, _, _) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          width: 400,
          height: double.infinity,
          child: Material(
            type: MaterialType.transparency,
            child: KBarSurface(
              elevated: true,
              child: SafeArea(child: sheet(c)),
            ),
          ),
        ),
      ),
      transitionBuilder: (c, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        if (reduceMotion) {
          return FadeTransition(opacity: curved, child: child);
        }
        final rtl = Directionality.of(c) == TextDirection.rtl;
        return SlideTransition(
          position: Tween(
            begin: Offset(rtl ? -1 : 1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = KStrings.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            KSpacing.s24,
            KSpacing.s8,
            KSpacing.s8,
            KSpacing.s8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
              ),
              ...actions,
              KIconButton(
                icon: KIcon.close,
                label: strings.close,
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: scrollable ? SingleChildScrollView(child: child) : child,
        ),
      ],
    );
  }
}
