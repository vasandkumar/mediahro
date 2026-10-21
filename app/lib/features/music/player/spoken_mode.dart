/// Who owns the engine's speed and silence setting while spoken word plays
/// (audiobooks, podcasts, Audiobookshelf). Each of those players keeps its
/// own speed and gives the engine back to normal when it is done; when one
/// takes over from another, the one leaving must not reset what the new one
/// has just set.
final class SpokenMode {
  Object? _owner;

  /// [player] starts spoken-word playback and owns the engine from now on.
  // ignore: use_setters_to_change_properties
  void claim(Object player) => _owner = player;

  /// [player] is leaving. True when it still owned the engine, so it should
  /// put the speed and silences back to normal; false when another player
  /// has taken over in the meantime and set its own.
  bool release(Object player) {
    if (_owner != player) return false;
    _owner = null;
    return true;
  }
}
