import 'package:flutter/foundation.dart';

/// Feature flags (docs/10 §1): every milestone's features ship behind a flag
/// until its gate passes; all flags are deleted before 1.0. Remote overrides
/// come only from the signed static JSON when the user enabled
/// configuration updates (docs/13 §2).
@immutable
final class Flags {
  const Flags(this._values);

  /// Milestone gates passed so far. Updated by the orchestrator at each gate.
  static const Flags defaults = Flags({
    'm1.engine': false,
    'm2.library': false,
    'm3.video': false,
    'm4.music': false,
    'm5.photos': false,
    'm6.servers': false,
    'm7.supporter': false,
  });

  final Map<String, bool> _values;

  bool isOn(String flag) =>
      _values[flag] ??
      (throw ArgumentError.value(flag, 'flag', 'unknown flag'));

  /// Applies local developer overrides (`--dart-define=MEDIAHRO_FLAGS=m1.engine,m3.video`).
  Flags withOverrides(String csv) {
    if (csv.isEmpty) return this;
    final next = Map<String, bool>.of(_values);
    for (final f
        in csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      if (!next.containsKey(f)) {
        throw ArgumentError.value(f, 'MEDIAHRO_FLAGS', 'unknown flag');
      }
      next[f] = true;
    }
    return Flags(next);
  }

  static Flags fromEnvironment() =>
      defaults.withOverrides(const String.fromEnvironment('MEDIAHRO_FLAGS'));
}
