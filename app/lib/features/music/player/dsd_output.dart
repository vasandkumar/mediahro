import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/platform/audio_output.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// The lowest DoP carrier rate: DSD64 (2.8224 MHz / 16) as 24-bit PCM.
const dsd64DopRate = 176400;

/// Native DSD over DoP (AUD-043, ADR-023). The engine plays a DSF or DFF
/// file as DoP only when the app lists `dop` for an exclusive, named device
/// and the OS has granted the bit-perfect path at the DoP rate; DoP sent to
/// a device that does not decode it is full-scale noise. So the app offers
/// "native DSD" only for a device that advertises a DoP rate **and** has
/// just granted [AudioOutputFacade.requestBitPerfect] at that rate with at
/// least 24 bits. Nothing else turns the option on.
final class DsdOutputGate {
  DsdOutputGate({required this.output, required this.prefs});

  final AudioOutputFacade output;
  final MusicPrefs prefs;

  /// A device the OS lists with exclusive mode and a DoP carrier rate. A
  /// necessary condition only: [offerFor] still asks the OS for the path.
  static bool advertisesDop(AudioDevice d) =>
      d.supportsExclusive && d.sampleRates.contains(dsd64DopRate);

  /// The OS device behind an engine device. The engine names a device with
  /// mpv's id (`aaudio/<os id>`, …) and a description; the facade names it
  /// with the OS id and product name. Matches the id's last segment to the
  /// OS id, then the description to the name; null when unsure, which keeps
  /// the offer off.
  static AudioDevice? facadeDeviceFor(
    EngineAudioDevice e,
    List<AudioDevice> devices,
  ) {
    if (e.isDefault || e.id == 'auto') return null;
    final tail = e.id.split('/').last;
    final byId = devices.where((d) => d.id == tail).toList();
    if (byId.length == 1) return byId.single;
    final byName = devices
        .where(
          (d) => d.name.trim().toLowerCase() == e.name.trim().toLowerCase(),
        )
        .toList();
    return byName.length == 1 ? byName.single : null;
  }

  /// The OS device behind [engineDevice] when native DSD may be offered for
  /// it, else null. Asks the OS for a bit-perfect path at the DSD64 DoP rate
  /// and 24 bits, then lets go of it: the engine asks again when it opens
  /// an item. A refusal, a lower grant, an unknown device or any platform
  /// error all mean no offer.
  Future<AudioDevice?> offerFor(EngineAudioDevice engineDevice) async {
    final List<AudioDevice> devices;
    try {
      devices = await output.devices();
    } on Object {
      return null;
    }
    final device = facadeDeviceFor(engineDevice, devices);
    if (device == null || !advertisesDop(device)) return null;
    try {
      final grant = await output.requestBitPerfect(
        device.id,
        sampleRate: dsd64DopRate,
        bitDepth: 24,
      );
      final ok =
          grant.bitPerfect &&
          (grant.sampleRate == null || grant.sampleRate == dsd64DopRate) &&
          (grant.bitDepth == null || grant.bitDepth! >= 24);
      return ok ? device : null;
    } on Object {
      return null;
    } finally {
      try {
        await output.releaseBitPerfect();
      } on Object {
        // Nothing was held.
      }
    }
  }

  /// The engine output for [engineDeviceId]: exclusive and named, with DoP
  /// listed when [nativeDsd], which the engine still verifies on the real
  /// output before every DSD item and otherwise plays as PCM.
  static AudioOutputConfig config(
    String? engineDeviceId, {
    required bool nativeDsd,
  }) => AudioOutputConfig(
    deviceId: engineDeviceId,
    exclusive: nativeDsd,
    nativeDsd: nativeDsd,
    passthroughCodecs: nativeDsd ? const ['dop'] : const [],
  );

  static const _key = 'dsd_output';

  /// The engine device native DSD was switched on for, if any.
  Future<String?> savedDevice() async =>
      (await prefs.readMap(_key))?['deviceId'] as String?;

  Future<void> save(String? engineDeviceId) => prefs.write(
    _key,
    engineDeviceId == null ? null : {'deviceId': engineDeviceId},
  );

  /// Puts the saved choice back on [engine] at start. The engine verifies
  /// the device and the OS grant per item, so a DAC that is gone plays PCM.
  Future<void> restore(PlaybackEngine engine) async {
    final id = await savedDevice();
    if (id == null) return;
    await engine.setAudioOutput(config(id, nativeDsd: true));
  }
}
