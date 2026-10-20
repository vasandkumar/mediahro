import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/video/text/open_text_services.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Records what the facades ask of the engines.
final class _Engines implements TextEngines {
  final ocr = <(List<String>, int, int)>[];
  final loaded = <String>[];
  LanguageGuess guess = const LanguageGuess('en', 0.99, reliable: true);

  @override
  Future<List<OcrLine>> recognize(
    Uint8List rgba,
    int width,
    int height, {
    required String tessdata,
    required List<String> languages,
  }) async {
    ocr.add((languages, width, height));
    return const [OcrLine('Hello there', 0.93, 10, 20, 300, 40)];
  }

  @override
  Future<LanguageGuess> identifyLanguage(String text) async => guess;

  @override
  Future<void> loadModel(String key, BergamotModelFiles files) async {
    loaded.add(key);
  }

  @override
  Future<List<String>> translate(String key, List<String> lines) async => [
    for (final l in lines) '[$key] $l',
  ];

  @override
  Future<void> close() async {}
}

final class _Source implements TranslationModelSource {
  _Source(this.pairs);

  final List<TranslationPair> pairs;
  final downloads = <String>[];

  @override
  Future<List<TranslationPair>> catalogue() async => pairs;

  @override
  Future<void> download(String from, String to, Directory dir) async {
    downloads.add('$from-$to');
    _model(dir);
  }
}

void _model(Directory dir) {
  dir.createSync(recursive: true);
  for (final f in ['model.x.intgemm.alphas.bin', 'vocab.x.spm']) {
    File('${dir.path}/$f').writeAsStringSync('');
  }
}

void main() {
  late Directory root;
  late _Engines engines;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('c1-text');
    engines = _Engines();
  });

  tearDown(() => root.delete(recursive: true));

  group('SUB-051 OCR (Tesseract, ADR-034)', () {
    late Directory tessdata;
    late OpenTextRecognition ocr;

    setUp(() {
      tessdata = Directory('${root.path}/tessdata')..createSync();
      ocr = OpenTextRecognition(
        engines: () async => engines,
        tessdata: tessdata,
      );
    });

    void install(String code) =>
        File('${tessdata.path}/$code.traineddata').writeAsStringSync('');

    test('SUB-051 BCP 47 tags map to Tesseract data', () {
      expect(tesseractCode('en-GB'), 'eng');
      expect(tesseractCode('de'), 'deu');
      expect(tesseractCode('zh-Hans'), 'chi_sim');
      expect(tesseractCode('zh-TW'), 'chi_tra');
      expect(tesseractCode('zh_Hant_HK'), 'chi_tra');
      expect(tesseractCode('nb'), 'nor');
      expect(tesseractCode('xx'), isNull);
    });

    test(
      'SUB-051 a language is supported once its data is on the device',
      () async {
        expect(await ocr.isSupported('fr'), isFalse);
        install('fra');
        expect(await ocr.isSupported('fr-CA'), isTrue);
      },
    );

    test(
      'SUB-051 recognises with the hinted languages that are installed',
      () async {
        install('eng');
        install('deu');
        final lines = await ocr.recognize(
          Uint8List(8 * 2 * 4),
          width: 8,
          height: 2,
          languageTags: ['de', 'fr'],
        );
        expect(engines.ocr.single.$1, ['deu']);
        expect(lines.single.text, 'Hello there');
        expect(lines.single.confidence, 0.93);
        expect(lines.single.width, 300);
      },
    );

    test(
      'SUB-051 without a usable hint: English, else any installed',
      () async {
        install('jpn');
        await ocr.recognize(Uint8List(4), width: 1, height: 1);
        expect(engines.ocr.last.$1, ['jpn']);
        install('eng');
        await ocr.recognize(
          Uint8List(4),
          width: 1,
          height: 1,
          languageTags: ['fr'],
        );
        expect(engines.ocr.last.$1, ['eng']);
      },
    );

    test('SUB-051 no language data, or a bad bitmap, is an error', () async {
      await expectLater(
        ocr.recognize(Uint8List(4), width: 1, height: 1),
        throwsStateError,
      );
      install('eng');
      await expectLater(
        ocr.recognize(Uint8List(3), width: 1, height: 1),
        throwsArgumentError,
      );
      await expectLater(
        ocr.recognize(Uint8List(4), width: 0, height: 1),
        throwsArgumentError,
      );
      await expectLater(
        ocr.recognize(Uint8List(4), width: 5000, height: 5000),
        throwsArgumentError,
      );
      expect(engines.ocr, isEmpty);
    });

    test('SUB-053 language ID: reliable guesses only, as BCP 47', () async {
      expect(await ocr.identifyLanguage('Hello there, how are you?'), 'en');
      engines.guess = const LanguageGuess('iw', 0.97, reliable: true);
      expect(await ocr.identifyLanguage('שלום'), 'he');
      engines.guess = const LanguageGuess('fr', 0.4, reliable: false);
      expect(await ocr.identifyLanguage('ok'), isNull);
      engines.guess = const LanguageGuess('und', 0, reliable: true);
      expect(await ocr.identifyLanguage('…'), isNull);
      expect(await ocr.identifyLanguage('  '), isNull);
    });
  });

  group('SUB-053 translation (Bergamot, ADR-034)', () {
    late Directory models;

    setUp(() => models = Directory('${root.path}/models')..createSync());

    OpenTranslation mt([TranslationModelSource? source]) => OpenTranslation(
      engines: () async => engines,
      models: models,
      source: source ?? const NoModelSource(),
    );

    test('SUB-053 no model host and nothing installed: no pairs', () async {
      expect(await mt().supportedPairs(), isEmpty);
      expect(await mt().isReady('en', 'de'), isFalse);
      await expectLater(mt().prepare('en', 'de'), throwsStateError);
    });

    test('SUB-053 installed models work without a host', () async {
      _model(Directory('${models.path}/en-de'));
      final t = mt();
      expect((await t.supportedPairs()).map((p) => '${p.from}-${p.to}'), [
        'en-de',
      ]);
      expect(await t.isReady('en-US', 'de'), isTrue);
      expect(await t.translate(['Hi', 'Bye'], from: 'en', to: 'de'), [
        '[en-de] Hi',
        '[en-de] Bye',
      ]);
    });

    test('SUB-053 pairs without a direct model go through English', () async {
      final source = _Source(const [
        TranslationPair('fr', 'en'),
        TranslationPair('en', 'de'),
        TranslationPair('en', 'fr'),
      ]);
      final t = mt(source);
      final pairs = (await t.supportedPairs()).map((p) => '${p.from}-${p.to}');
      expect(pairs, containsAll(['fr-en', 'en-de', 'en-fr', 'fr-de']));
      expect(pairs, isNot(contains('fr-fr')));
      expect(await t.isReady('fr', 'de'), isFalse);
      await t.prepare('fr', 'de');
      expect(source.downloads, ['fr-en', 'en-de']);
      expect(await t.isReady('fr', 'de'), isTrue);
      await t.prepare('fr', 'de');
      expect(source.downloads, hasLength(2), reason: 'already installed');
      expect(await t.translate(['Bonjour'], from: 'fr', to: 'de'), [
        '[en-de] [fr-en] Bonjour',
      ]);
      expect(engines.loaded, ['fr-en', 'en-de']);
    });

    test('SUB-053 translating without the model is an error', () async {
      final t = mt(_Source(const [TranslationPair('en', 'de')]));
      await expectLater(
        t.translate(['Hi'], from: 'en', to: 'de'),
        throwsStateError,
      );
      expect(await t.translate([], from: 'en', to: 'de'), isEmpty);
    });
  });
}
