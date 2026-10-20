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
