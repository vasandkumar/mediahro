import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

// Tesseract arrives with mediahro-deps v2026.10.5 (B4a); CLD3 and Bergamot
// (with Mediahro's C shims) at B4a's next slot (ADR-034). Until a library
// is in the build, its native tests are skipped with that reason.
String? _skip(NativeLibrary lib) => NativeLibraries.isAvailable(lib)
    ? null
    : switch (lib) {
        NativeLibrary.tesseract =>
          'needs libtesseract from mediahro-deps v2026.10.5 (B4a)',
        _ =>
          'needs ${lib.baseName} with its C shim from mediahro-deps (B4a, '
              'ADR-034)',
      };

void main() {
  group('SUB-051 subtitle bitmaps for OCR', () {
    Uint8List px(List<List<int>> rgba) =>
        Uint8List.fromList([for (final p in rgba) ...p]);

    test('SUB-051 light subtitle text becomes dark on white', () {
      final grey = subtitleToGrey(
        px([
          [0, 0, 0, 0], // transparent
          [255, 255, 255, 255], // white text
          [0, 0, 0, 255], // black outline
          [255, 255, 255, 128], // half-transparent text
        ]),
        4,
        1,
      );
      expect(grey[0], 255);
      expect(grey[1], 0);
      expect(grey[2], 255);
      expect(grey[3], closeTo(127, 1));
    });

    test('SUB-051 a short buffer is refused', () {
      expect(() => subtitleToGrey(Uint8List(4), 2, 1), throwsArgumentError);
    });
  });

  group('SUB-053 Bergamot model files', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('c1-mt'));
    tearDown(() => dir.delete(recursive: true));

    void touch(String name) => File('${dir.path}/$name').writeAsStringSync('');

    test('SUB-053 a shared vocabulary and a shortlist', () {
      touch('model.ende.intgemm.alphas.bin');
      touch('vocab.ende.spm');
      touch('lex.50.50.ende.s2t.bin');
      final f = BergamotModelFiles.inFolder(dir)!;
      expect(f.model, endsWith('model.ende.intgemm.alphas.bin'));
      expect(f.sourceVocab, f.targetVocab);
      expect(f.shortlist, endsWith('lex.50.50.ende.s2t.bin'));
      final config = f.config();
      expect(config, contains('models:\n  - '));
      expect(config, contains('shortlist:\n'));
      expect(config, contains('gemm-precision: int8shiftAlphaAll'));
      expect(config, contains('beam-size: 1'));
    });

    test('SUB-053 separate vocabularies, no shortlist', () {
      touch('model.enja.intgemm.alphas.bin');
      touch('srcvocab.enja.spm');
      touch('trgvocab.enja.spm');
      final f = BergamotModelFiles.inFolder(dir)!;
      expect(f.sourceVocab, endsWith('srcvocab.enja.spm'));
      expect(f.targetVocab, endsWith('trgvocab.enja.spm'));
      expect(f.shortlist, isNull);
      expect(f.config(), isNot(contains('shortlist')));
    });

    test('SUB-053 a folder without a model or vocabulary is no model', () {
      touch('vocab.ende.spm');
      expect(BergamotModelFiles.inFolder(dir), isNull);
      expect(
        BergamotModelFiles.inFolder(Directory('${dir.path}/missing')),
        isNull,
      );
    });

    test("SUB-053 quotes in paths can't break the config", () {
      const f = BergamotModelFiles(
        model: "/m/it's/model.bin",
        sourceVocab: '/m/v.spm',
        targetVocab: '/m/v.spm',
      );
      expect(f.config(), contains("'/m/it''s/model.bin'"));
    });
  });

  group('ADR-034 text worker', () {
    test('ADR-034 errors from the worker isolate reach the caller', () async {
      final w = await TextWorker.spawn();
      addTearDown(w.close);
      await expectLater(
        w.translate('en-de', ['Hello']),
        throwsA(isA<StateError>()),
      );
      // The worker keeps serving after an error.
      await expectLater(
        w.translate('en-fr', ['Hello']),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'ADR-034 a missing library is reported, not a crash',
      () async {
        final w = await TextWorker.spawn();
        addTearDown(w.close);
        await expectLater(
          w.identifyLanguage('Hello there'),
          throwsA(isA<NativeLibraryUnavailable>()),
        );
      },
      skip: NativeLibraries.isAvailable(NativeLibrary.cld3)
          ? 'cld3 is in this build'
          : null,
    );

    test('ADR-034 calls after close fail', () async {
      final w = await TextWorker.spawn();
      await w.close();
      await expectLater(
        w.translate('en-de', ['x']),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ADR-034 native', () {
    test('SUB-051 Tesseract loads, and refuses missing language data', () {
      // Opening needs language data; the library itself must load.
      expect(
        () => TesseractOcr.open('/nonexistent', ['eng']),
        throwsA(isA<StateError>()),
      );
    }, skip: _skip(NativeLibrary.tesseract));

    test('SUB-053 CLD3 tells English from German', () {
      final id = Cld3LanguageIdentifier.open();
      addTearDown(id.close);
      expect(
        id.identify('The quick brown fox jumps over the lazy dog.').code,
        'en',
      );
      expect(
        id.identify('Der schnelle braune Fuchs springt über den Hund.').code,
        'de',
      );
    }, skip: _skip(NativeLibrary.cld3));

    test('SUB-053 Bergamot starts', () {
      BergamotTranslator.open().close();
    }, skip: _skip(NativeLibrary.bergamot));
  });
}
