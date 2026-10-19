import 'package:flutter/material.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/foundation/strings.dart';
import 'package:mediahro_design/src/theme.dart';
import 'package:mediahro_design/src/tokens.dart';

/// Empty state (docs/06 §9): illustration-free, one sentence, actions.
class KEmptyState extends StatelessWidget {
  const KEmptyState({
    required this.message,
    this.title,
    this.actions = const [],
    super.key,
  });

  final String? title;
  final String message;

  /// Usually the three add buttons (`KButton`s).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KSpacing.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Semantics(
                  header: true,
                  child: Text(
                    title!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: KSpacing.s8),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              if (actions.isNotEmpty) const SizedBox(height: KSpacing.s24),
              for (final (i, a) in actions.indexed) ...[
                if (i > 0) const SizedBox(height: KSpacing.s12),
                a,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state (docs/06 §8): a plain sentence plus one action ("Try again",
/// "Choose another"). Announced as a live region.
class KErrorState extends StatelessWidget {
  const KErrorState({
    required this.message,
    required this.action,
    this.secondaryAction,
    super.key,
  });

  final String message;
  final Widget action;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KSpacing.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline,
                size: 32,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: KSpacing.s12),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: KSpacing.s24),
              action,
              if (secondaryAction != null) ...[
                const SizedBox(height: KSpacing.s12),
                secondaryAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder block. Lists show skeleton rows (never spinners)
/// while loading (docs/06 §9). A soft pulse runs unless reduced motion is
/// on.
class KSkeleton extends StatefulWidget {
  const KSkeleton({this.width, this.height = 14, this.radius = 4, super.key});

  final double? width;
  final double height;
  final double radius;

  @override
  State<KSkeleton> createState() => _KSkeletonState();
}

class _KSkeletonState extends State<KSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        !KAccessibility.reduceMotion(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!animate) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.08 + 0.06 * _pulse.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Skeleton list rows with the same geometry as `KRow`.
class KSkeletonRows extends StatelessWidget {
  const KSkeletonRows({this.count = 6, this.withLeading = true, super.key});

  final int count;
  final bool withLeading;

  @override
  Widget build(BuildContext context) {
    final strings = KStrings.of(context);
    final scale = MediaQuery.textScalerOf(context);
    return Semantics(
      label: strings.loading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpacing.s16,
                    vertical: KSpacing.s8,
                  ),
                  child: Row(
                    children: [
                      if (withLeading) ...[
                        KSkeleton(
                          width: 40,
                          height: 40,
                          radius: Theme.of(context).mediahroShape.controlRadius
                              .clamp(0, 8),
                        ),
                        const SizedBox(width: KSpacing.s16),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.7 : 0.55,
                              child: KSkeleton(height: scale.scale(14)),
                            ),
                            const SizedBox(height: KSpacing.s8),
                            FractionallySizedBox(
                              widthFactor: 0.4,
                              child: KSkeleton(height: scale.scale(12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
