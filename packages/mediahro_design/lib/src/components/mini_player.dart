import 'package:flutter/material.dart';
import 'package:mediahro_design/src/components/button.dart';
import 'package:mediahro_design/src/foundation/accessibility.dart';
import 'package:mediahro_design/src/foundation/materials.dart';
import 'package:mediahro_design/src/icons.dart';
import 'package:mediahro_design/src/tokens.dart';

/// Persistent mini-player bar (docs/06 §3.2) shown by the shell above the
/// navigation bar (never over the video player). Tapping it opens Now
/// Playing; play/pause and next stay one tap away.
class KMiniPlayer extends StatelessWidget {
  const KMiniPlayer({
    required this.title,
    required this.playing,
    required this.onPlayPause,
    required this.playLabel,
    required this.pauseLabel,
    required this.onOpen,
    required this.openLabel,
    this.subtitle,
    this.artwork,
    this.progress,
    this.onNext,
    this.nextLabel,
    super.key,
  }) : assert(onNext == null || nextLabel != null, 'Next needs a label');

  final String title;
  final String? subtitle;
  final Widget? artwork;
  final bool playing;
  final VoidCallback onPlayPause;
  final String playLabel;
  final String pauseLabel;
  final VoidCallback onOpen;

  /// Spoken hint for opening Now Playing.
  final String openLabel;

  /// 0–1, drawn as a thin line along the top edge.
  final double? progress;
  final VoidCallback? onNext;
  final String? nextLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = KAccessibility.reduceMotion(context);
    return KBarSurface(
      elevated: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress != null)
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 2,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    onTapHint: openLabel,
                    child: InkWell(
                      onTap: onOpen,
                      splashFactory: reduceMotion
                          ? NoSplash.splashFactory
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KSpacing.s12,
                          vertical: KSpacing.s8,
                        ),
                        child: Row(
                          children: [
                            if (artwork != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(KRadius.xs),
                                child: SizedBox.square(
                                  dimension: 44,
                                  child: artwork,
                                ),
                              ),
                              const SizedBox(width: KSpacing.s12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(title, style: theme.textTheme.bodyLarge),
                                  if (subtitle != null)
                                    Text(
                                      subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                KIconButton(
                  icon: playing ? KIcon.pause : KIcon.play,
                  label: playing ? pauseLabel : playLabel,
                  onPressed: onPlayPause,
                ),
                if (onNext != null)
                  KIconButton(
                    icon: KIcon.next,
                    label: nextLabel!,
                    onPressed: onNext,
                  ),
                const SizedBox(width: KSpacing.s4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
