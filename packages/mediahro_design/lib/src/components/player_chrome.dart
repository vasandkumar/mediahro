import 'package:flutter/material.dart';
import 'package:mediahro_design/src/components/button.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/foundation/strings.dart';
import 'package:mediahro_design/src/icons.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

/// Video player chrome (docs/06 §3.1): video on true black, a top bar
/// (back, title, source badge, actions) and a bottom panel (seek bar, time,
/// transport, chips) over scrims.
///
/// - Visibility is owned by the caller (auto-hide after 3 s, tap to toggle);
///   use [shouldAutoHide] — chrome stays up while a screen reader or switch
///   control is active.
/// - Never uses glass materials over video; with reduced transparency the
///   scrims become opaque panels.
/// - The transport row is laid out left-to-right in every locale.
class KPlayerChrome extends StatelessWidget {
  const KPlayerChrome({
    required this.video,
    required this.visible,
    required this.title,
    this.subtitle,
    this.sourceBadge,
    this.onBack,
    this.topActions = const [],
    this.seekBar,
    this.elapsed,
    this.remaining,
    this.transport = const [],
    this.chips = const [],
    this.trailingActions = const [],
    this.overlay,
    super.key,
  });

  /// The video surface.
  final Widget video;
  final bool visible;
  final String title;
  final String? subtitle;
  final String? sourceBadge;
  final VoidCallback? onBack;
  final List<Widget> topActions;
  final Widget? seekBar;

  /// Elapsed / remaining labels (tap to toggle is the caller's).
  final Widget? elapsed;
  final Widget? remaining;

  /// Play/pause and ±10 s ([KIconButton]s with `color: Colors.white`).
  final List<Widget> transport;

  /// Speed, subtitle and audio chips.
  final List<Widget> chips;

  /// Lock, rotate, fullscreen.
  final List<Widget> trailingActions;

  /// Gesture feedback (brightness/volume ring) above the video.
  final Widget? overlay;

  static bool shouldAutoHide(BuildContext context) =>
      !KAccessibility.assistiveNavigation(context);

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.mediahro;
    final darkTheme = MediahroTheme.build(
      ThemeSpec(family: base.mediahroShape.family, brightness: Brightness.dark),
    );
    final reduceMotion = KAccessibility.reduceMotion(context);
    final opaque = KAccessibility.reduceTransparency(context);
    final strings = KStrings.of(context);
    final shown = visible || !shouldAutoHide(context);
    final textStyle = darkTheme.textTheme.bodyMedium!.copyWith(
      color: colors.playerChrome,
    );

    Decoration panel({required bool top}) => opaque
        ? BoxDecoration(color: colors.playerSurface.withValues(alpha: 0.92))
        : BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                colors.playerScrim,
                colors.playerScrim.withValues(alpha: 0),
              ],
            ),
          );

    final topBar = DecoratedBox(
      decoration: panel(top: true),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.s4,
            KSpacing.s4,
            KSpacing.s4,
            KSpacing.s24,
          ),
          child: Row(
            children: [
              if (onBack != null)
                KIconButton(
                  icon: KIcon.back,
                  label: strings.back,
                  onPressed: onBack,
                  color: Colors.white,
                ),
              const SizedBox(width: KSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: darkTheme.textTheme.titleMedium!.copyWith(
                          color: colors.playerChrome,
                        ),
                      ),
                    ),
                    if (subtitle != null || sourceBadge != null)
                      Wrap(
                        spacing: KSpacing.s8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (subtitle != null)
                            Text(subtitle!, style: textStyle),
                          if (sourceBadge != null)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white70),
                                borderRadius: BorderRadius.circular(KRadius.xs),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: KSpacing.s4,
                                ),
                                child: Text(
                                  sourceBadge!,
                                  style: darkTheme.textTheme.labelSmall!
                                      .copyWith(color: colors.playerChrome),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              ...topActions,
            ],
          ),
        ),
      ),
    );

    final bottomPanel = DecoratedBox(
      decoration: panel(top: false),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.s12,
            KSpacing.s32,
            KSpacing.s12,
            KSpacing.s8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (seekBar != null)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      if (elapsed != null)
                        DefaultTextStyle(style: textStyle, child: elapsed!),
                      const SizedBox(width: KSpacing.s8),
                      Expanded(child: seekBar!),
                      const SizedBox(width: KSpacing.s8),
                      if (remaining != null)
                        DefaultTextStyle(style: textStyle, child: remaining!),
                    ],
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: KSpacing.s4,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: transport,
                    ),
                  ),
                  Wrap(
                    spacing: KSpacing.s8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [...chips, ...trailingActions],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Theme(
      data: darkTheme,
      child: ColoredBox(
        color: colors.playerSurface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            video,
            ?overlay,
            AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: KMotion.resolve(
                KMotion.base,
                reduceMotion: reduceMotion,
              ),
              child: IgnorePointer(
                ignoring: !shown,
                child: ExcludeSemantics(
                  excluding: !shown,
                  // Scrolls instead of overflowing when 200 % text makes the
                  // panels taller than a landscape phone.
                  child: LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [topBar, bottomPanel],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
