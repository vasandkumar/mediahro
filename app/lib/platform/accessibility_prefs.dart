/// System accessibility preferences that Flutter does not expose (SYS-008,
/// ADR-038): `AccessibilityManager.isAudioDescriptionRequested` on Android 13+
/// (API 33; false below), the platform's audio-description preference on
/// Apple (MediaAccessibility "prefers descriptive audio"), and false on
/// Windows until a system setting exists. Captions are separate
/// (`CaptionStyleFacade`, ADR-030). More preferences can be added here later.
abstract interface class AccessibilityPrefsFacade {
  /// Whether the user asked for audio descriptions. False when the OS has no
  /// such setting.
  Future<bool> audioDescriptionRequested();

  /// Emits the new value whenever the user changes the preference.
  Stream<bool> get audioDescriptionChanges;
}

/// Default for platforms and tests with no native implementation (ADR-038):
/// audio description is never requested and never changes.
final class UnsupportedAccessibilityPrefs implements AccessibilityPrefsFacade {
  const UnsupportedAccessibilityPrefs();

  @override
  Future<bool> audioDescriptionRequested() async => false;

  @override
  Stream<bool> get audioDescriptionChanges => const Stream<bool>.empty();
}
