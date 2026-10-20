import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mediahro_ffi/src/bergamot/bergamot_translator.dart';
import 'package:mediahro_ffi/src/cld3/language_identifier.dart';
import 'package:mediahro_ffi/src/tesseract/tesseract_ocr.dart';

/// The on-device text engines (ADR-034) as the app's facades use them.
abstract interface class TextEngines {
  /// OCR of subtitle RGBA with the [languages] (Tesseract codes) in
  /// [tessdata].
  Future<List<OcrLine>> recognize(
    Uint8List rgba,
    int width,
    int height, {
    required String tessdata,
    required List<String> languages,
  });

  Future<LanguageGuess> identifyLanguage(String text);

  /// Loads a translation model under [key] (e.g. `en-de`), once.
  Future<void> loadModel(String key, BergamotModelFiles files);

  Future<List<String>> translate(String key, List<String> lines);

  Future<void> close();
}

/// [TextEngines] on one long-lived worker isolate, which keeps Tesseract,
/// CLD3 and Bergamot loaded between calls (PRIV-005: nothing heavy on the
/// UI isolate). Calls are answered in order.
final class TextWorker implements TextEngines {
  TextWorker._(this._isolate, this._send, this._replies);

  static Future<TextWorker> spawn() async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      replies.sendPort,
      debugName: 'mediahro-text',
    );
    final events = replies.asBroadcastStream();
    final send = await events.first as SendPort;
    final worker = TextWorker._(isolate, send, replies);
    events.listen(worker._reply);
    return worker;
  }

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _pending = <int, Completer<Object?>>{};
  var _next = 0;
  var _closed = false;

  void _reply(Object? message) {
    final (id, result, error, stack) =
        message! as (int, Object?, Object?, String?);
    final c = _pending.remove(id);
    if (c == null) return;
    if (error != null) {
      c.completeError(error, StackTrace.fromString(stack ?? ''));
    } else {
      c.complete(result);
    }
  }

  Future<T> _run<T>(_Job job) {
    if (_closed) return Future.error(StateError('text worker closed'));
    final id = _next++;
    final c = _pending[id] = Completer<Object?>();
    _send.send((id, job));
    return c.future.then((v) => v as T);
  }

  @override
  Future<List<OcrLine>> recognize(
    Uint8List rgba,
    int width,
    int height, {
    required String tessdata,
    required List<String> languages,
  }) => _run(_Ocr(rgba, width, height, tessdata, languages));

  @override
  Future<LanguageGuess> identifyLanguage(String text) => _run(_Identify(text));

  @override
  Future<void> loadModel(String key, BergamotModelFiles files) =>
      _run(_Load(key, files));

  @override
  Future<List<String>> translate(String key, List<String> lines) =>
      _run(_Translate(key, lines));

  @override
  Future<void> close() async {
    if (_closed) return;
    await _run<void>(const _Close());
    _closed = true;
    _replies.close();
    _isolate.kill();
    for (final c in _pending.values) {
      c.completeError(StateError('text worker closed'));
    }
    _pending.clear();
  }

  static void _main(SendPort replies) {
    final jobs = ReceivePort();
    replies.send(jobs.sendPort);
    final engines = _Engines();
    jobs.listen((message) {
      final (id, job) = message! as (int, _Job);
      try {
        replies.send((id, job.run(engines), null, null));
      } on Object catch (e, s) {
        replies.send((id, null, e, s.toString()));
      }
      if (job is _Close) jobs.close();
    });
  }
}

/// The engines, created on first use inside the worker.
final class _Engines {
  TesseractOcr? ocr;
  String? ocrKey;
  Cld3LanguageIdentifier? cld3;
  BergamotTranslator? bergamot;

  TesseractOcr tesseract(String tessdata, List<String> languages) {
    final key = '$tessdata|${languages.join('+')}';
    if (ocrKey != key) {
      ocr?.close();
      ocr = null;
      ocr = TesseractOcr.open(tessdata, languages);
      ocrKey = key;
    }
    return ocr!;
  }

  void close() {
    ocr?.close();
    cld3?.close();
    bergamot?.close();
  }
}

sealed class _Job {
  const _Job();

  Object? run(_Engines e);
}

final class _Ocr extends _Job {
  const _Ocr(this.rgba, this.width, this.height, this.tessdata, this.langs);

  final Uint8List rgba;
  final int width;
  final int height;
  final String tessdata;
  final List<String> langs;

  @override
  Object? run(_Engines e) => e
      .tesseract(tessdata, langs)
      .recognize(subtitleToGrey(rgba, width, height), width, height);
}

final class _Identify extends _Job {
  const _Identify(this.text);

  final String text;

  @override
  Object? run(_Engines e) =>
      (e.cld3 ??= Cld3LanguageIdentifier.open()).identify(text);
}

final class _Load extends _Job {
  const _Load(this.key, this.files);

  final String key;
  final BergamotModelFiles files;

  @override
  Object? run(_Engines e) {
    (e.bergamot ??= BergamotTranslator.open()).load(key, files);
    return null;
  }
}

final class _Translate extends _Job {
  const _Translate(this.key, this.lines);

  final String key;
  final List<String> lines;

  @override
  Object? run(_Engines e) {
    final b = e.bergamot;
    if (b == null) throw StateError('model $key not loaded');
    return b.translate(key, lines);
  }
}

final class _Close extends _Job {
  const _Close();

  @override
  Object? run(_Engines e) {
    e.close();
    return null;
  }
}
