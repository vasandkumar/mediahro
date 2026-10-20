/// Keeps sensitive screens (the photo vault, IMG-011) out of screenshots,
/// screen recordings and the app switcher (ADR-039).
///
/// Android sets `FLAG_SECURE` (also blanks the recents thumbnail). iOS shows
/// a blur overlay on resign-active and reports `UIScreen.isCaptured`. macOS
/// sets `NSWindow.sharingType = .none`. Windows calls
/// `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`.
abstract interface class SecureWindowFacade {
  /// Turns protection on or off for the app window. Callers enable it when a
  /// vault opens and disable it when the vault locks or closes.
  Future<void> setSecure({required bool secure});

  /// Emits true while the OS reports the screen being captured or mirrored
  /// (iOS, and Windows/macOS where detectable), false when that stops.
  /// Empty where the platform cannot tell.
  Stream<bool> get captureActive;
}

/// Default for platforms and tests with no native implementation: nothing is
/// protected and no capture is ever reported.
final class UnsupportedSecureWindow implements SecureWindowFacade {
  const UnsupportedSecureWindow();

  @override
  Future<void> setSecure({required bool secure}) async {}

  @override
  Stream<bool> get captureActive => const Stream<bool>.empty();
}
