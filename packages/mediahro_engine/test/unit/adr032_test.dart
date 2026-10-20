import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/pcm_storage.dart';
import 'package:mediahro_engine/testing.dart';

/// ADR-032: offline audio decode (SUB-050, SUB-052, MUS-010) without
/// libmpv: the fake engine, the crossfader and the PCM storage.
void main() {
  final src = UriSource(Uri.parse('https://example.test/film.mkv'));

  group('ADR-032 decodeAudio doubles', () {
    test('SUB-050 the fake engine returns its PCM in chunks, cut', () async {
      final e = FakePlaybackEngine()
        ..decodedAudio = Float32List.fromList([
          for (var i = 0; i < 16000 * 3; i++) i / 16000,
        ]);
      addTearDown(e.dispose);
      final chunks = await e.decodeAudio(src).toList();
      expect(chunks, hasLength(6));
      expect(chunks.fold(0, (n, c) => n + c.length), 16000 * 3);
      final part = await e
          .decodeAudio(
            src,
            trackId: 2,
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 2),
          )
          .toList();
      expect(part.fold(0, (n, c) => n + c.length), 16000);
      expect(part.first.first, closeTo(1, 1e-6));
      expect(e.decodeRequests.last.trackId, 2);
      expect(e.decodeRequests.last.sampleRate, 16000);
      expect(e.calls.where((c) => c == 'decodeAudio'), hasLength(2));
    });

    test('SUB-052 fake decode failures arrive as stream errors', () async {
      final e = FakePlaybackEngine()
        ..decodeAudioError = const EngineException(
          EngineError(code: EngineErrorCode.unsupportedFormat),
        );
      addTearDown(e.dispose);
      await expectLater(e.decodeAudio(src), emitsError(isA<EngineException>()));
    });

    test('MUS-010 the crossfader decodes through its core', () async {
      final cores = <FakePlaybackEngine>[];
      final e = CrossfadingEngine(() {
        final c = FakePlaybackEngine(role: EngineRole.music)
          ..decodedAudio = Float32List(11025);
        cores.add(c);
        return c;
      });
      addTearDown(e.dispose);
      final chunks = await e
          .decodeAudio(src, sampleRate: 11025, mono: false)
          .toList();
      expect(chunks.fold(0, (n, c) => n + c.length), 11025);
      expect(cores.first.decodeRequests.single.mono, isFalse);
    });
  });

  group('ADR-032 PCM storage', () {
    test('SUB-050 delivered PCM is given back to the OS', () async {
      final storage = await PcmStorage.create(slice: false);
      addTearDown(storage.dispose);
      expect(storage.slicePath, isNull);
      final pcm = File(storage.pcmPath);
      const mb = 1 << 20;
      for (var i = 0; i < 3; i++) {
        pcm.writeAsBytesSync(
          Uint8List(mb)..fillRange(0, mb, 0x7f),
          mode: FileMode.append,
        );
      }
      storage.release(mb * 5 ~/ 2);
      if (Platform.isWindows ||
          Platform.isAndroid ||
          Platform.isLinux ||
          Platform.isMacOS) {
        expect(storage.released, 2 * mb, reason: 'whole MB, block-aligned');
        final head = pcm.openSync()..setPositionSync(mb * 2 - 4);
        expect(head.readSync(8), [0, 0, 0, 0, 0x7f, 0x7f, 0x7f, 0x7f]);
        head.closeSync();
      }
      // The length stays, so offsets keep their meaning.
      expect(storage.pcmLength, 3 * mb);
    });
  });
}
