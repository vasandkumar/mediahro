import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

// The open, on-device text services every build uses (ADR-034): Tesseract
// for OCR, CLD3 for language ID, Bergamot for translation. Nothing here
// talks to the network except a translation-model download the user has
// agreed to, through [TranslationModelSource].

/// Largest subtitle bitmap OCR accepts (PRIV-005 limits): a 4K frame.
const int maxOcrPixels = 4096 * 2160;

/// Tesseract's language-data code for a BCP 47 [tag], or null when
/// Tesseract has no model for it.
String? tesseractCode(String tag) {
  final parts = tag.replaceAll('_', '-').toLowerCase().split('-');
  final lang = parts.first;
  if (lang == 'zh') {
    final traditional =
        parts.contains('hant') ||
        parts.contains('tw') ||
        parts.contains('hk') ||
        parts.contains('mo');
    return traditional ? 'chi_tra' : 'chi_sim';
  }
  return _tesseractCodes[lang];
}

const _tesseractCodes = {
  'af': 'afr', 'ar': 'ara', 'az': 'aze', 'be': 'bel', 'bg': 'bul', //
  'bn': 'ben', 'bs': 'bos', 'ca': 'cat', 'cs': 'ces', 'cy': 'cym',
  'da': 'dan', 'de': 'deu', 'el': 'ell', 'en': 'eng', 'eo': 'epo',
  'es': 'spa', 'et': 'est', 'eu': 'eus', 'fa': 'fas', 'fi': 'fin',
  'fil': 'fil', 'fr': 'fra', 'ga': 'gle', 'gl': 'glg', 'gu': 'guj',
  'he': 'heb', 'hi': 'hin', 'hr': 'hrv', 'hu': 'hun', 'hy': 'hye',
  'id': 'ind', 'is': 'isl', 'it': 'ita', 'ja': 'jpn', 'ka': 'kat',
  'kk': 'kaz', 'km': 'khm', 'kn': 'kan', 'ko': 'kor', 'la': 'lat',
  'lo': 'lao', 'lt': 'lit', 'lv': 'lav', 'mk': 'mkd', 'ml': 'mal',
  'mn': 'mon', 'mr': 'mar', 'ms': 'msa', 'my': 'mya', 'nb': 'nor',
  'ne': 'nep', 'nl': 'nld', 'nn': 'nor', 'no': 'nor', 'pa': 'pan',
  'pl': 'pol', 'pt': 'por', 'ro': 'ron', 'ru': 'rus', 'si': 'sin',
  'sk': 'slk', 'sl': 'slv', 'sq': 'sqi', 'sr': 'srp', 'sv': 'swe',
  'sw': 'swa', 'ta': 'tam', 'te': 'tel', 'th': 'tha', 'tl': 'tgl',
  'tr': 'tur', 'uk': 'ukr', 'ur': 'urd', 'uz': 'uzb', 'vi': 'vie',
  'yi': 'yid',
};

/// BCP 47 for a CLD3 code: CLD3 still uses a few retired codes.
String bcp47FromCld3(String code) => switch (code) {
  'iw' => 'he',
  'jw' => 'jv',
  'in' => 'id',
  final c => c,
};

/// [TextRecognitionFacade] over Tesseract and CLD3 (ADR-034). Language
/// data (`<code>.traineddata`) lives in [tessdata]; a language without
/// its file is not supported until the data is added.
final class OpenTextRecognition implements TextRecognitionFacade {
  OpenTextRecognition({
    required Future<TextEngines> Function() engines,
    required this.tessdata,
  }) : _spawn = engines;

  final Future<TextEngines> Function() _spawn;
  final Directory tessdata;
  Future<TextEngines>? _engines;

  Future<TextEngines> get _e => _engines ??= _spawn();

  bool _installed(String code) =>
      File('${tessdata.path}/$code.traineddata').existsSync();

  @override
  Future<bool> isSupported(String languageTag) async {
    final code = tesseractCode(languageTag);
    return code != null && _installed(code);
  }

  @override
  Future<List<RecognizedLine>> recognize(
    Uint8List rgba, {
    required int width,
    required int height,
    List<String> languageTags = const [],
  }) async {
    if (width <= 0 || height <= 0 || width * height > maxOcrPixels) {
      throw ArgumentError('bitmap size $width × $height out of range');
    }
    if (rgba.length < width * height * 4) {
      throw ArgumentError.value(rgba.length, 'rgba', 'shorter than w × h × 4');
    }
    final wanted = {
      for (final t in languageTags)
        if (tesseractCode(t) case final c? when _installed(c)) c,
    };
    if (wanted.isEmpty) {
      // No hint, or no data for it: English if present, else any.
      if (_installed('eng')) {
        wanted.add('eng');
      } else if (tessdata.existsSync()) {
        final any =
            tessdata
                .listSync()
                .whereType<File>()
                .map((f) => f.uri.pathSegments.last)
                .where((n) => n.endsWith('.traineddata'))
                .map((n) => n.substring(0, n.length - '.traineddata'.length))
                .where((c) => c != 'osd')
                .toList()
              ..sort();
        if (any.isNotEmpty) wanted.add(any.first);
      }
    }
    if (wanted.isEmpty) throw StateError('no OCR language data installed');
    final lines = await (await _e).recognize(
      rgba,
      width,
      height,
      tessdata: tessdata.path,
      languages: wanted.toList(),
    );
    return [
      for (final l in lines)
        RecognizedLine(l.text, l.confidence, l.left, l.top, l.width, l.height),
    ];
  }

  @override
  Future<String?> identifyLanguage(String text) async {
    if (text.trim().isEmpty) return null;
    final guess = await (await _e).identifyLanguage(text);
    if (!guess.reliable || guess.code == 'und') return null;
    return bcp47FromCld3(guess.code);
  }
}

/// Where translation models come from. Downloads happen only from
/// [TranslationFacade.prepare], which the player calls after the user
/// agrees (PRIV-004).
abstract interface class TranslationModelSource {
  /// Directions that can be downloaded, by ISO 639-1 code.
  Future<List<TranslationPair>> catalogue();

  /// Downloads the model files for one direction into [dir].
  Future<void> download(String from, String to, Directory dir);
}

/// No model host yet: the PRIV-004 endpoint is added once the model host
/// and licences are confirmed (ADR-034). Installed models still work.
final class NoModelSource implements TranslationModelSource {
  const NoModelSource();

  @override
  Future<List<TranslationPair>> catalogue() async => const [];

  @override
  Future<void> download(String from, String to, Directory dir) =>
      Future.error(StateError('no translation model host configured'));
}

/// [TranslationFacade] over Bergamot (ADR-034). One model per direction
/// in `<models>/<from>-<to>/`; a pair with no direct model goes through
/// English, as Firefox Translations does.
final class OpenTranslation implements TranslationFacade {
  OpenTranslation({
    required Future<TextEngines> Function() engines,
    required this.models,
    this.source = const NoModelSource(),
  }) : _spawn = engines;

  final Future<TextEngines> Function() _spawn;
  final Directory models;
  final TranslationModelSource source;
  Future<TextEngines>? _engines;

  Future<TextEngines> get _e => _engines ??= _spawn();

  static String _lang(String tag) =>
      tag.replaceAll('_', '-').split('-').first.toLowerCase();

  Directory _dir(String from, String to) =>
      Directory('${models.path}/$from-$to');

  bool _installed(String from, String to) =>
      BergamotModelFiles.inFolder(_dir(from, to)) != null;

  Future<Set<(String, String)>> _directions() async {
    final out = <(String, String)>{
      for (final p in await source.catalogue()) (_lang(p.from), _lang(p.to)),
    };
    if (models.existsSync()) {
      for (final d in models.listSync().whereType<Directory>()) {
        final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final parts = name.split('-');
        if (parts.length == 2 && _installed(parts[0], parts[1])) {
          out.add((parts[0], parts[1]));
        }
      }
    }
    return out;
  }

  /// The model directions that translate [from] → [to], or null.
  Future<List<(String, String)>?> _route(String from, String to) async {
    final all = await _directions();
    if (all.contains((from, to))) return [(from, to)];
    if (from != 'en' &&
        to != 'en' &&
        all.contains((from, 'en')) &&
        all.contains(('en', to))) {
      return [(from, 'en'), ('en', to)];
    }
    return null;
  }

  @override
  Future<List<TranslationPair>> supportedPairs() async {
    final all = await _directions();
    final pairs = <(String, String)>{...all};
    final intoEnglish = [
      for (final (f, t) in all)
        if (t == 'en') f,
    ];
    final fromEnglish = [
      for (final (f, t) in all)
        if (f == 'en') t,
    ];
    for (final f in intoEnglish) {
      for (final t in fromEnglish) {
        if (f != t) pairs.add((f, t));
      }
    }
    final sorted = pairs.toList()
      ..sort((a, b) => '${a.$1}-${a.$2}'.compareTo('${b.$1}-${b.$2}'));
    return [for (final (f, t) in sorted) TranslationPair(f, t)];
  }

  @override
  Future<bool> isReady(String from, String to) async {
    final route = await _route(_lang(from), _lang(to));
    return route != null && route.every((d) => _installed(d.$1, d.$2));
  }

  @override
  Future<void> prepare(String from, String to) async {
    final route = await _route(_lang(from), _lang(to));
    if (route == null) throw StateError('no model for $from → $to');
    for (final (f, t) in route) {
      if (!_installed(f, t)) await source.download(f, t, _dir(f, t));
    }
  }

  @override
  Future<List<String>> translate(
    List<String> lines, {
    required String from,
    required String to,
  }) async {
    if (lines.isEmpty) return const [];
    final route = await _route(_lang(from), _lang(to));
    if (route == null) throw StateError('no model for $from → $to');
    final engines = await _e;
    var current = lines;
    for (final (f, t) in route) {
      final files = BergamotModelFiles.inFolder(_dir(f, t));
      if (files == null) throw StateError('model $f-$t is not installed');
      await engines.loadModel('$f-$t', files);
      current = await engines.translate('$f-$t', current);
      if (current.length != lines.length) {
        throw StateError('translation changed the line count');
      }
    }
    return current;
  }
}

/// One text worker for OCR, language ID and translation, started on
/// first use and stopped with the app.
final textEnginesProvider = Provider<Future<TextEngines> Function()>((ref) {
  Future<TextEngines>? worker;
  ref.onDispose(() {
    if (worker case final w?) unawaited(w.then((e) => e.close()));
  });
  return () => worker ??= TextWorker.spawn();
});

/// The overrides that make the open text services the app's OCR and
/// translation (ADR-034). Each platform's bindings add these.
List<Override> openTextServiceOverrides() => [
  textRecognitionProvider.overrideWith(
    (ref) => OpenTextRecognition(
      engines: ref.watch(textEnginesProvider),
      tessdata: Directory(
        '${ref.watch(appDataDirectoryProvider).path}/tessdata',
      ),
    ),
  ),
  translationProvider.overrideWith(
    (ref) => OpenTranslation(
      engines: ref.watch(textEnginesProvider),
      models: Directory(
        '${ref.watch(appDataDirectoryProvider).path}/translation_models',
      ),
    ),
  ),
];
