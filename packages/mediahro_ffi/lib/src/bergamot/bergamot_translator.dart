import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/bergamot/bergamot_bindings.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:meta/meta.dart';

/// The files of one Bergamot model (one direction, e.g. en→de), as the
/// Firefox translation models ship them: an int8 model, one shared or two
/// separate SentencePiece vocabularies, and an optional lexical shortlist.
@immutable
final class BergamotModelFiles {
  const BergamotModelFiles({
    required this.model,
    required this.sourceVocab,
    required this.targetVocab,
    this.shortlist,
  });

  final String model;
  final String sourceVocab;
  final String targetVocab;
  final String? shortlist;

  /// Finds the files in [dir] by their usual names (`model.*.bin`,
  /// `vocab.*.spm` or `srcvocab.*.spm` + `trgvocab.*.spm`,
  /// `lex.*.s2t.bin`); null when the model or a vocabulary is missing.
  static BergamotModelFiles? inFolder(Directory dir) {
    if (!dir.existsSync()) return null;
    final names = {
      for (final e in dir.listSync().whereType<File>())
        e.uri.pathSegments.last: e.path,
    };
    String? first(bool Function(String) test) {
      final keys = names.keys.where(test).toList()..sort();
      return keys.isEmpty ? null : names[keys.first];
    }

    final model = first((n) => n.startsWith('model.') && n.endsWith('.bin'));
    final shared = first((n) => n.startsWith('vocab.') && n.endsWith('.spm'));
    final src = first((n) => n.startsWith('srcvocab.') && n.endsWith('.spm'));
    final trg = first((n) => n.startsWith('trgvocab.') && n.endsWith('.spm'));
    final lex = first((n) => n.startsWith('lex.') && n.endsWith('.s2t.bin'));
    final sourceVocab = src ?? shared;
    final targetVocab = trg ?? shared;
    if (model == null || sourceVocab == null || targetVocab == null) {
      return null;
    }
    return BergamotModelFiles(
      model: model,
      sourceVocab: sourceVocab,
      targetVocab: targetVocab,
      shortlist: lex,
    );
  }

  /// The Marian/Bergamot config for these files: greedy decoding with the
  /// int8 settings Firefox Translations uses, one thread (the worker
  /// isolate is the parallelism).
  String config() {
    String q(String path) => "'${path.replaceAll("'", "''")}'";
    final buf = StringBuffer()
      ..writeln('models:')
      ..writeln('  - ${q(model)}')
      ..writeln('vocabs:')
      ..writeln('  - ${q(sourceVocab)}')
      ..writeln('  - ${q(targetVocab)}');
    if (shortlist case final s?) {
      buf
        ..writeln('shortlist:')
        ..writeln('  - ${q(s)}')
        ..writeln('  - false');
    }
    buf
      ..writeln('beam-size: 1')
      ..writeln('normalize: 1.0')
      ..writeln('word-penalty: 0')
      ..writeln('max-length-break: 128')
      ..writeln('mini-batch-words: 1024')
      ..writeln('workspace: 128')
      ..writeln('max-length-factor: 2.0')
      ..writeln('skip-cost: true')
      ..writeln('cpu-threads: 0')
      ..writeln('quiet: true')
      ..writeln('quiet-translation: true')
      ..writeln('gemm-precision: int8shiftAlphaAll')
      ..writeln('alignment: soft');
    return buf.toString();
  }
}

/// The Bergamot translator with loaded models (ADR-034, SUB-053). Runs on
/// a worker isolate: loading a model and translating are both heavy.
final class BergamotTranslator {
  BergamotTranslator._(this._b, this._service);

  factory BergamotTranslator.open({
    int cacheSize = 2000,
    BergamotBindings? bindings,
  }) {
    final b =
        bindings ??
        BergamotBindings(NativeLibraries.open(NativeLibrary.bergamot));
    final s = b.mh_bergamot_new(cacheSize);
    if (s == ffi.nullptr) throw StateError('mh_bergamot_new failed');
    return BergamotTranslator._(b, s);
  }

  final BergamotBindings _b;
  ffi.Pointer<mh_bergamot> _service;
  final _models = <String, ffi.Pointer<mh_bergamot_model>>{};

  /// Loads [files] under [key] (e.g. `en-de`); a second load of the same
  /// key is a no-op.
  void load(String key, BergamotModelFiles files) {
    if (_service == ffi.nullptr) throw StateError('closed');
    if (_models.containsKey(key)) return;
    final config = files.config().toNativeUtf8();
    const errLen = 512;
    final err = calloc<ffi.Char>(errLen);
    try {
      final m = _b.mh_bergamot_load(_service, config.cast(), err, errLen);
      if (m == ffi.nullptr) {
        throw StateError(
          'Bergamot could not load $key: ${err.cast<Utf8>().toDartString()}',
        );
      }
      _models[key] = m;
    } finally {
      calloc
        ..free(config)
        ..free(err);
    }
  }

  bool isLoaded(String key) => _models.containsKey(key);

  /// Translates [lines] with the model loaded under [key], keeping order
  /// and count.
  List<String> translate(String key, List<String> lines) {
    final model = _models[key];
    if (model == null) throw StateError('model $key not loaded');
    if (lines.isEmpty) return const [];
    final n = lines.length;
    final input = calloc<ffi.Pointer<ffi.Char>>(n);
    final output = calloc<ffi.Pointer<ffi.Char>>(n);
    try {
      for (var i = 0; i < n; i++) {
        input[i] = lines[i].toNativeUtf8().cast();
      }
      if (_b.mh_bergamot_translate(_service, model, input, n, output) != 0) {
        throw StateError('Bergamot translation failed');
      }
      return [
        for (var i = 0; i < n; i++)
          () {
            final t = output[i].cast<Utf8>().toDartString();
            _b.mh_bergamot_free_text(output[i]);
            return t;
          }(),
      ];
    } finally {
      for (var i = 0; i < n; i++) {
        if (input[i] != ffi.nullptr) calloc.free(input[i]);
      }
      calloc
        ..free(input)
        ..free(output);
    }
  }

  void close() {
    _models.values.forEach(_b.mh_bergamot_model_free);
    _models.clear();
    if (_service == ffi.nullptr) return;
    _b.mh_bergamot_free(_service);
    _service = ffi.nullptr;
  }
}
