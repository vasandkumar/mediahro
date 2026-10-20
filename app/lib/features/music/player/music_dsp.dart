import 'dart:async';
import 'dart:convert';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:meta/meta.dart';

/// Centre frequencies of the 10-band graphic EQ (AUD-005).
const eqBandsHz = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// Built-in presets (dB per band). Ids are stable; names come from l10n.
const builtInEqPresets = <String, List<double>>{
  'flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'bassBoost': [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
  'trebleBoost': [0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
  'vocal': [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1],
  'rock': [4, 3, 2, 0, -1, -1, 1, 2, 3, 4],
  'pop': [-1, 1, 3, 4, 3, 1, -1, -1, 1, 2],
  'jazz': [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  'classical': [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
  'electronic': [5, 4, 1, 0, -2, 2, 1, 1, 4, 5],
  'loudness': [5, 3, 0, 0, -1, 0, -1, 0, 3, 4],
};

/// The music sound settings shown in the EQ sheet (MUS-006 "EQ quick
/// access") and applied to the music engine.
@immutable
final class MusicSound {
  const MusicSound({
    this.eqEnabled = false,
    this.gains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.preset = 'flat',
    this.preampDb = 0,
    this.loudness = LoudnessMode.off,
    this.crossfade = Duration.zero,
    this.crossfadeOnSkip = false,
  });

  factory MusicSound.fromJson(Map<String, Object?>? j) {
    if (j == null) return const MusicSound();
    final g = [
      if (j['gains'] case final List<Object?> l)
        for (final v in l) (jsonDouble(v) ?? 0).clamp(-12.0, 12.0),
    ];
    return MusicSound(
      eqEnabled: j['eq'] == true,
      gains: g.length == eqBandsHz.length ? g : const MusicSound().gains,
      preset: j['preset'] is String ? j['preset']! as String : 'flat',
      preampDb: (jsonDouble(j['preamp']) ?? 0).clamp(-12.0, 12.0),
      loudness:
          LoudnessMode.values
              .where((m) => m.name == j['loudness'])
              .firstOrNull ??
          LoudnessMode.off,
      crossfade: Duration(
        milliseconds: (jsonInt(j['crossfadeMs']) ?? 0).clamp(0, 12000),
      ),
      crossfadeOnSkip: j['crossfadeSkip'] == true,
    );
  }

  final bool eqEnabled;
  final List<double> gains;

  /// Built-in preset id, `custom:<eq_preset id>`, or `custom`.
  final String preset;
  final double preampDb;
  final LoudnessMode loudness;

  /// AUD-003 crossfade on natural ends (0 = gapless).
  final Duration crossfade;

  /// Also crossfade manual skips.
  final bool crossfadeOnSkip;

  AudioDspChain get chain => AudioDspChain(
    graphicEq: eqEnabled ? gains : const [],
    preampDb: eqEnabled ? preampDb : 0,
    loudness: loudness,
  );

  TransitionConfig get transition => TransitionConfig(
    naturalEnd: crossfade,
    manualSkip: crossfadeOnSkip ? crossfade : Duration.zero,
  );

  MusicSound copyWith({
    bool? eqEnabled,
    List<double>? gains,
    String? preset,
    double? preampDb,
    LoudnessMode? loudness,
    Duration? crossfade,
    bool? crossfadeOnSkip,
  }) => MusicSound(
    eqEnabled: eqEnabled ?? this.eqEnabled,
    gains: gains ?? this.gains,
    preset: preset ?? this.preset,
    preampDb: preampDb ?? this.preampDb,
    loudness: loudness ?? this.loudness,
    crossfade: crossfade ?? this.crossfade,
    crossfadeOnSkip: crossfadeOnSkip ?? this.crossfadeOnSkip,
  );

  Map<String, Object?> toJson() => {
    'eq': eqEnabled,
    'gains': gains,
    'preset': preset,
    'preamp': preampDb,
    'loudness': loudness.name,
    'crossfadeMs': crossfade.inMilliseconds,
    'crossfadeSkip': crossfadeOnSkip,
  };
}

/// A user-saved EQ preset (`eq_preset` table).
@immutable
final class CustomEqPreset {
  const CustomEqPreset(this.id, this.name, this.gains, this.preampDb);

  final int id;
  final String name;
  final List<double> gains;
  final double preampDb;
}

/// Loads, persists and applies [MusicSound] to the music engine.
final class MusicDsp {
  MusicDsp({required this.engine, required this.prefs, required this.db});

  final PlaybackEngine engine;
  final MusicPrefs prefs;
  final LibraryDatabase db;

  final _changes = StreamController<MusicSound>.broadcast();
  MusicSound _sound = const MusicSound();

  MusicSound get sound => _sound;

  Stream<MusicSound> get changes => Stream.multi((l) {
    l.add(_sound);
    final s = _changes.stream.listen(l.add, onDone: l.close);
    l.onCancel = s.cancel;
  });

  Future<void> load() async {
    _sound = MusicSound.fromJson(await prefs.readMap('sound'));
    await _apply();
    if (!_changes.isClosed) _changes.add(_sound);
  }

  Future<void> update(MusicSound s) async {
    _sound = s;
    if (!_changes.isClosed) _changes.add(s);
    await _apply();
    await prefs.write('sound', s.toJson());
  }

  /// Applies a built-in preset or a saved one.
  Future<void> applyPreset(String id) async {
    final builtIn = builtInEqPresets[id];
    if (builtIn != null) {
      await update(
        _sound.copyWith(eqEnabled: true, gains: builtIn, preset: id),
      );
      return;
    }
    final custom = (await customPresets())
        .where((p) => 'custom:${p.id}' == id)
        .firstOrNull;
    if (custom != null) {
      await update(
        _sound.copyWith(
          eqEnabled: true,
          gains: custom.gains,
          preampDb: custom.preampDb,
          preset: id,
        ),
      );
    }
  }

  Future<List<CustomEqPreset>> customPresets() async => [
    for (final r in await db.select(db.eqPresets).get())
      if (_decodeGains(r.definition) case (final g, final pre))
        CustomEqPreset(r.id, r.name, g, pre),
  ];

  /// Saves the current curve as a named preset and selects it.
  Future<int> savePreset(String name) async {
    final id = await db
        .into(db.eqPresets)
        .insert(
          EqPresetsCompanion.insert(
            name: name,
            definition: jsonEncode({
              'graphicEq': _sound.gains,
              'preampDb': _sound.preampDb,
            }),
          ),
        );
    await update(_sound.copyWith(preset: 'custom:$id'));
    return id;
  }

  Future<void> deletePreset(int id) async {
    await (db.delete(db.eqPresets)..where((p) => p.id.equals(id))).go();
    if (_sound.preset == 'custom:$id') {
      await update(_sound.copyWith(preset: 'custom'));
    }
  }

  Future<void> dispose() => _changes.close();

  Future<void> _apply() async {
    await engine.setAudioDsp(_sound.chain);
    await engine.setTransition(_sound.transition);
  }

  static (List<double>, double)? _decodeGains(String definition) {
    try {
      final j = jsonDecode(definition);
      if (j is! Map<String, Object?>) return null;
      final g = [
        if (j['graphicEq'] case final List<Object?> l)
          for (final v in l) jsonDouble(v) ?? 0,
      ];
      if (g.length != eqBandsHz.length) return null;
      return (g, jsonDouble(j['preampDb']) ?? 0);
    } on FormatException {
      return null;
    }
  }
}
