import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/music/fingerprint/fingerprint_service.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../test/features/music/music_test_support.dart';

/// Lane C2 on real devices (MUS-010): the engine decodes a song to PCM
/// (ADR-032) and Chromaprint, dynamically linked from B2's build, turns it
/// into an AcoustID fingerprint: stable for the same audio, different for
/// different audio. The lookup itself is covered by unit tests; it needs the
/// owner's AcoustID key and the network.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('c2fp');
  });
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  });

  /// [seconds] of a tone that changes pitch every half second, 22.05 kHz
  /// mono WAV: enough structure for Chromaprint to hear a melody.
  Uint8List melody(int seconds, int seed) {
    const rate = 22050;
    final frames = rate * seconds;
    final b = ByteData(44 + frames * 2);
    void str(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + frames * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, frames * 2, Endian.little);
    final notes = [220.0, 277.18, 329.63, 440.0, 392.0, 246.94, 349.23];
    for (var i = 0; i < frames; i++) {
      final note = notes[((i ~/ (rate ~/ 2)) * seed + seed) % notes.length];
      final v = (math.sin(2 * math.pi * note * i / rate) * 9000).round();
      b.setInt16(44 + i * 2, v, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  testWidgets('MUS-010 a song is decoded and fingerprinted on the device', (
    tester,
  ) async {
    if (!MpvEngine.isAvailable) {
      return markTestSkipped('blocked: libmpv is not bundled in this build');
    }
    await tester.runAsync(() async {
      File('${dir.path}/a.wav').writeAsBytesSync(melody(20, 3));
      File('${dir.path}/a2.wav').writeAsBytesSync(melody(20, 3));
      File('${dir.path}/b.wav').writeAsBytesSync(melody(20, 5));
      final db = LibraryDatabase.memory();
      final seed = MusicSeed(db);
      await seed.source(dir.uri.toString());
      for (final n in ['a', 'a2', 'b']) {
        await seed.song('$n.wav', title: n, durationMs: 20000);
      }
      final tracks = {
        for (final t in await MusicLibrary(db).songs()) t.title: t,
      };
      final engine = MpvEngine(EngineRole.music);
      final fingerprinter = TrackFingerprinter(
        engine: engine,
        files: localMusicFiles(db),
      );
      final a = await fingerprinter.of(tracks['a']!);
      final a2 = await fingerprinter.of(tracks['a2']!);
      final b = await fingerprinter.of(tracks['b']!);
      expect(a.encoded, isNotEmpty);
      expect(a.encoded.startsWith('AQAA'), isTrue);
      expect(a.durationSeconds, 20);
      expect(a2.encoded, a.encoded);
      expect(b.encoded, isNot(a.encoded));
      await engine.dispose();
      await db.close();
    });
  });
}
