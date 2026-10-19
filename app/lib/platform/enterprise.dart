import 'package:meta/meta.dart';

/// Managed app configuration (B2B-001): Android Enterprise restrictions,
/// Apple MDM managed app config, Windows registry / MSIX policy. Read-only;
/// managed values win over user settings (docs/05 §6).
abstract interface class ManagedConfigFacade {
  Future<Map<String, ManagedValue>> read();
  Stream<Map<String, ManagedValue>> get changes;
}

@immutable
sealed class ManagedValue {
  const ManagedValue();
}

final class ManagedString extends ManagedValue {
  const ManagedString(this.value);
  final String value;
}

final class ManagedBool extends ManagedValue {
  // A value wrapper; the positional bool is the whole point.
  // ignore: avoid_positional_boolean_parameters
  const ManagedBool(this.value);
  final bool value;
}

final class ManagedInt extends ManagedValue {
  const ManagedInt(this.value);
  final int value;
}

final class ManagedList extends ManagedValue {
  const ManagedList(this.values);
  final List<String> values;
}

/// Kiosk / signage (B2B-002): lock task (A), Guided Access / Single App Mode
/// compatibility (I), full-screen kiosk (M W), start on boot.
abstract interface class KioskFacade {
  Future<bool> isSupported();
  Future<void> enter();
  Future<void> exit();
  Stream<bool> get isActive;
  Future<void> setStartOnBoot({required bool enabled});
}
