import 'package:mediahro/platform/android/gen/power_api.pigeon.dart';
import 'package:mediahro/platform/power_status.dart';

/// [PowerStatusFacade] on Android (ADR-033): `PowerManager` thermal status
/// (NONE → nominal, LIGHT → fair, MODERATE → serious, SEVERE and above →
/// critical) and battery saver (`PowerStatusModule.kt`). [changes] starts
/// with the current state and then emits only on change.
final class AndroidPowerStatus implements PowerStatusFacade {
  AndroidPowerStatus({
    PowerStatusHostApi? api,
    Stream<PowerStatusMsg> Function()? events,
  }) : _api = api ?? PowerStatusHostApi(),
       _events = events ?? powerStatusChanges;

  final PowerStatusHostApi _api;
  final Stream<PowerStatusMsg> Function() _events;

  @override
  Future<PowerStatus> current() async => _status(await _api.current());

  @override
  late final Stream<PowerStatus> changes = _events().map(_status);

  static PowerStatus _status(PowerStatusMsg m) => PowerStatus(
    thermal: ThermalLevel.values[m.thermal.index],
    batterySaver: m.batterySaver,
  );
}
