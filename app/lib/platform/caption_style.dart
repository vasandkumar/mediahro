import 'package:meta/meta.dart';

/// The user's system caption preferences, so subtitles can follow them
/// (SUB-014, docs/06 §7, ADR-030): CaptioningManager (A),
/// MACaptionAppearance (I M), ClosedCaptionProperties (W).
abstract interface class CaptionStyleFacade {
  /// The current system style, or null when the OS has no caption settings.
  Future<SystemCaptionStyle?> current();

  /// Emits whenever the user changes the system caption settings.
  Stream<SystemCaptionStyle> get changes;
}

enum CaptionEdge { none, outline, dropShadow, raised, depressed }

@immutable
final class SystemCaptionStyle {
  const SystemCaptionStyle({
    required this.enabled,
    this.fontFamily,
    this.scale = 1,
    this.foregroundArgb,
    this.backgroundArgb,
    this.windowArgb,
    this.edge = CaptionEdge.none,
    this.edgeArgb,
  });

  /// Whether the user turned system captions on.
  final bool enabled;

  /// The chosen typeface family, or null for the system default.
  final String? fontFamily;

  /// Text size relative to the default (1.0).
  final double scale;

  /// Colours as 0xAARRGGBB; null means "not set by the user".
  final int? foregroundArgb;
  final int? backgroundArgb;
  final int? windowArgb;

  final CaptionEdge edge;
  final int? edgeArgb;
}
