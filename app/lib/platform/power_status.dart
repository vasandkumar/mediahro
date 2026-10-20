import 'package:meta/meta.dart';

/// Thermal and battery-saver state (ADR-033), so heavy rendering (VID-038
/// shaders, VID-039 interpolation) can step down before the OS throttles:
/// PowerManager thermal status + power-save mode (A), ProcessInfo
/// thermalState + Low Power Mode (I M), PowerManager.EnergySaverStatus (W).
abstract interface class PowerStatusFacade {
  Future<PowerStatus> current();

  /// Emits whenever the thermal level or battery saver changes.
  Stream<PowerStatus> get changes;
}

/// Ordered from coolest to hottest; maps to Android's THERMAL_STATUS_* and
/// Apple's ProcessInfo.ThermalState.
enum ThermalLevel { nominal, fair, serious, critical }

@immutable
final class PowerStatus {
  const PowerStatus({required this.thermal, required this.batterySaver});

  final ThermalLevel thermal;

  /// Battery saver / Low Power Mode / Energy Saver is on.
  final bool batterySaver;
}
