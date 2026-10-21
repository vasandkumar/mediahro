import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/painting.dart' show BoxFit;
import 'package:meta/meta.dart';

/// Displays, HDR and mode matching (VID-031, VID-036, VID-040, VID-070,
/// VID-071): Surface.setFrameRate / preferredDisplayModeId (A), UIScreen (I),
/// CGDisplay modes (M), DXGI + refresh switching (W).
abstract interface class DisplayFacade {
  Future<List<DisplayInfo>> displays();
  Stream<List<DisplayInfo>> get changes;

  /// Switches [displayId] to a mode matching [fps]; true if switched.
  Future<bool> matchFrameRate(String displayId, double fps);
  Future<void> restoreDisplayMode(String displayId);
  Future<void> keepScreenOn({required bool on});

  /// Window brightness for the player gesture (A I), 0–1; null resets.
  Future<void> setWindowBrightness(double? value);
  Future<void> setOrientationLock(OrientationLock lock);

  /// Opens a presentation on the external display [displayId] so content can
  /// be drawn there while the controls stay on the device (IMG-012 slideshow,
  /// CAST-004; ADR-044). The app renders into the separate Flutter view or
  /// surface named by the returned handle's [PresentationHandle.id].
  ///
  /// Null when the platform cannot present on that display (or the display is
  /// gone). Only the app's own rendering is shown: callers must not send
  /// DRM-protected or vault (sensitive, ADR-043) content without the user's
  /// confirmation. The presentation closes by itself when the display
  /// disconnects (see [changes]).
  Future<PresentationHandle?> openPresentation(String displayId);

  /// Closes a presentation from [openPresentation]; a no-op for a handle that
  /// is already closed.
  Future<void> closePresentation(PresentationHandle handle);

  /// Shows [frame] on the presentation (ADR-044 amendment 1). The external
  /// screen shows only what the app sends, so a sender decodes, rotates and
  /// colour-manages the image itself and passes encoded pixels. A no-op for a
  /// handle that is closed. The default for platforms without presentations
  /// is also a no-op.
  Future<void> present(PresentationHandle handle, PresentationFrame frame);
}

/// How one frame replaces the one before it on a presentation.
enum PresentationTransition { none, crossfade }

/// A slow pan and zoom over a frame's image (Ken Burns): the visible region
/// moves from [from] to [to] over [duration], both in normalised image
/// coordinates (0..1). The sender passes no motion when reduced motion is on.
@immutable
final class PresentationMotion {
  const PresentationMotion({
    required this.from,
    required this.to,
    required this.duration,
  });

  final Rect from;
  final Rect to;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is PresentationMotion &&
      other.from == from &&
      other.to == to &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(from, to, duration);
}

/// What an external display shows (ADR-044 amendment 1).
@immutable
final class PresentationFrame {
  const PresentationFrame({
    this.image,
    this.fit = BoxFit.contain,
    this.transition = PresentationTransition.none,
    this.transitionDuration = Duration.zero,
    this.motion,
    this.caption,
  });

  /// An empty (black) screen.
  static const PresentationFrame clear = PresentationFrame();

  /// Encoded image bytes (PNG or JPEG), already decoded, rotated and
  /// colour-managed by the sender; null shows black.
  final Uint8List? image;
  final BoxFit fit;
  final PresentationTransition transition;
  final Duration transitionDuration;
  final PresentationMotion? motion;
  final String? caption;

  @override
  bool operator ==(Object other) =>
      other is PresentationFrame &&
      _same(other.image, image) &&
      other.fit == fit &&
      other.transition == transition &&
      other.transitionDuration == transitionDuration &&
      other.motion == motion &&
      other.caption == caption;

  @override
  int get hashCode => Object.hash(
    image == null ? null : Object.hashAll(image!),
    fit,
    transition,
    transitionDuration,
    motion,
    caption,
  );

  static bool _same(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// An open presentation on an external display (ADR-044).
@immutable
final class PresentationHandle {
  const PresentationHandle({required this.id, required this.displayId});

  /// Identifies the Flutter view or surface to render into.
  final int id;

  /// The [DisplayInfo.id] of the display it covers.
  final String displayId;

  @override
  bool operator ==(Object other) =>
      other is PresentationHandle &&
      other.id == id &&
      other.displayId == displayId;

  @override
  int get hashCode => Object.hash(id, displayId);

  @override
  String toString() => 'PresentationHandle($id, $displayId)';
}

enum OrientationLock { auto, landscape, portrait, followVideo }

@immutable
final class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.name,
    required this.refreshRate,
    this.supportedRefreshRates = const [],
    this.hdr = false,
    this.peakNits,
    this.isExternal = false,
    this.iccProfile,
  });

  final String id;
  final String name;
  final double refreshRate;
  final List<double> supportedRefreshRates;
  final bool hdr;
  final double? peakNits;
  final bool isExternal;

  /// System display profile path (VID-040, M W).
  final String? iccProfile;
}

/// System Picture-in-Picture (VID-067): Android PiP,
/// AVPictureInPictureController + AVSampleBufferDisplayLayer (I),
/// native PiP (M), compact overlay (W).
abstract interface class PipFacade {
  Future<bool> isSupported();
  Future<bool> enter({required double aspectRatio});
  Future<void> exit();

  /// Auto-PiP on leave (opt-in).
  Future<void> setAutoEnter({required bool enabled});

  /// The playing video's shape (width / height), whenever it changes
  /// (ADR-028). Android needs it before PiP starts, for auto-enter and
  /// [OrientationLock.followVideo]; it also resizes an open PiP window.
  Future<void> setAspectRatio(double aspectRatio);
  Stream<bool> get isActive;
}
