import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path_provider/path_provider.dart';

part 'settings_store.freezed.dart';
part 'settings_store.g.dart';

/// A typed setting (CORE-006). Ids are `<section>.<name>` where `<section>`
/// is a `SettingsSectionId` name (`playback.seekStep`,
/// `privacy.endpoint.tmdb`); "Reset section" clears every id with that
/// prefix. Lanes declare their keys in their own folders.
@immutable
final class SettingKey<T extends Object> {
  const SettingKey(
    this.id, {
    required this.defaultValue,
    required this.decodeJson,
    required this.encodeJson,
  });

  static SettingKey<bool> boolean(String id, {required bool defaultValue}) =>
      SettingKey<bool>(
        id,
        defaultValue: defaultValue,
        decodeJson: (j) => j is bool ? j : null,
        encodeJson: (v) => v,
      );

  static SettingKey<int> integer(
    String id, {
    required int defaultValue,
    int? min,
    int? max,
  }) => SettingKey<int>(
    id,
    defaultValue: defaultValue,
    decodeJson: (j) {
      if (j is! int) return null;
      if ((min != null && j < min) || (max != null && j > max)) return null;
      return j;
    },
    encodeJson: (v) => v,
  );

  static SettingKey<double> decimal(
    String id, {
    required double defaultValue,
    double? min,
    double? max,
  }) => SettingKey<double>(
    id,
    defaultValue: defaultValue,
    decodeJson: (j) {
      if (j is! num) return null;
      final v = j.toDouble();
      if ((min != null && v < min) || (max != null && v > max)) return null;
      return v;
    },
    encodeJson: (v) => v,
  );

  static SettingKey<String> text(String id, {required String defaultValue}) =>
      SettingKey<String>(
        id,
        defaultValue: defaultValue,
        decodeJson: (j) => j is String ? j : null,
        encodeJson: (v) => v,
      );

  /// Stored by enum name, so reordering an enum never changes values.
  static SettingKey<E> enumeration<E extends Enum>(
    String id,
    List<E> values, {
    required E defaultValue,
  }) => SettingKey<E>(
    id,
    defaultValue: defaultValue,
    decodeJson: (j) => j is String ? values.asNameMap()[j] : null,
    encodeJson: (v) => v.name,
  );

  static SettingKey<List<String>> stringList(
    String id, {
    List<String> defaultValue = const [],
  }) => SettingKey<List<String>>(
    id,
    defaultValue: defaultValue,
    decodeJson: (j) => j is List && j.every((e) => e is String)
        ? List<String>.unmodifiable(j.cast<String>())
        : null,
    encodeJson: (v) => v,
  );

  final String id;
  final T defaultValue;

  /// Returns null for values of the wrong type or out of range.
  final T? Function(Object? json) decodeJson;
  final Object? Function(T value) encodeJson;

  /// The section prefix of [id].
  String get section => id.split('.').first;

  T? decode(Object? json) => decodeJson(json);
  Object? encode(T value) => encodeJson(value);

  @override
  bool operator ==(Object other) => other is SettingKey && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SettingKey($id)';
}

/// Immutable view of all settings: user values with the managed-config
/// overlay on top (B2B-001: managed values are read-only and win).
@immutable
final class SettingsSnapshot {
  const SettingsSnapshot({
    this.values = const {},
    this.managed = const {},
    this.revision = 0,
  });

  final Map<String, Object?> values;
  final Map<String, Object?> managed;
  final int revision;

  T get<T extends Object>(SettingKey<T> key) {
    if (managed.containsKey(key.id)) {
      final m = key.decode(managed[key.id]);
      if (m != null) return m;
    }
    return key.decode(values[key.id]) ?? key.defaultValue;
  }

  bool isManaged(SettingKey<Object> key) =>
      managed.containsKey(key.id) && key.decode(managed[key.id]) != null;

  /// Whether the user changed [key] from its default.
  bool isSet(SettingKey<Object> key) => values.containsKey(key.id);
}

/// The JSON document written to disk and used for import/export (CORE-006).
@freezed
abstract class SettingsDocument with _$SettingsDocument {
  const factory SettingsDocument({
    @Default(SettingsDocument.currentSchema) int schema,
    @Default(<String, Object?>{}) Map<String, Object?> values,
    DateTime? exportedAt,
  }) = _SettingsDocument;

  factory SettingsDocument.fromJson(Map<String, Object?> json) =>
      _$SettingsDocumentFromJson(json);

  static const int currentSchema = 1;

  /// Marker key so arbitrary JSON is not mistaken for a settings file.
  static const String format = 'mediahro.settings';
}

/// Thrown when writing a setting the organisation manages.
final class ManagedSettingException implements Exception {
  const ManagedSettingException(this.id);

  final String id;

  @override
  String toString() => 'ManagedSettingException($id)';
}

/// Thrown by [SettingsStore.importJson] for files that are not Mediahro
/// settings or come from a newer schema.
final class SettingsImportException implements Exception {
  const SettingsImportException(this.reason);

  final SettingsImportError reason;

  @override
  String toString() => 'SettingsImportException(${reason.name})';
}

enum SettingsImportError { notJson, notSettings, newerSchema }

@immutable
final class SettingsImportResult {
  const SettingsImportResult({
    required this.imported,
    required this.skippedManaged,
    required this.skippedInvalid,
  });

  final int imported;
  final int skippedManaged;
  final int skippedInvalid;
}

/// Where settings live between launches.
abstract interface class SettingsPersistence {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> document);
}

/// `settings.json` in the app support directory, written atomically
/// (temp file + rename). A corrupt file is kept as `settings.corrupt.json`
/// and the app starts with defaults rather than failing.
final class FileSettingsPersistence implements SettingsPersistence {
  FileSettingsPersistence({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}settings.json',
  );

  @override
  Future<Map<String, Object?>?> load() async {
    final f = await _file();
    if (!f.existsSync()) return null;
    try {
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Fall through to quarantine.
    }
    await f.rename('${f.path.substring(0, f.path.length - 5)}.corrupt.json');
    return null;
  }

  @override
  Future<void> save(Map<String, Object?> document) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
      flush: true,
    );
    await tmp.rename(f.path);
  }
}

/// In-memory persistence for tests and previews.
final class MemorySettingsPersistence implements SettingsPersistence {
  MemorySettingsPersistence([this.document]);

  Map<String, Object?>? document;
  int saves = 0;

  @override
  Future<Map<String, Object?>?> load() async => document;

  @override
  Future<void> save(Map<String, Object?> document) async {
    saves++;
    this.document = jsonDecode(jsonEncode(document)) as Map<String, Object?>;
  }
}

/// Owns the settings document (CORE-006): typed reads and writes, reset per
/// section, import/export as JSON, the managed-config overlay, and debounced
/// atomic persistence. Unknown keys (from newer versions or lanes not in
/// this build) are preserved.
class SettingsStore extends ChangeNotifier {
  SettingsStore(
    this._persistence, {
    this.saveDelay = const Duration(milliseconds: 300),
  });

  /// Loads from [persistence] and returns a ready store.
  static Future<SettingsStore> open([
    SettingsPersistence? persistence,
    Duration? saveDelay = const Duration(milliseconds: 300),
  ]) async {
    final store = SettingsStore(
      persistence ?? FileSettingsPersistence(),
      saveDelay: saveDelay,
    );
    await store.load();
    return store;
  }

  final SettingsPersistence _persistence;

  /// Debounce for writes; null writes on every change (tests).
  final Duration? saveDelay;
  final Completer<void> _ready = Completer<void>();
  SettingsSnapshot _snapshot = const SettingsSnapshot();
  Timer? _saveTimer;
  Future<void>? _pendingSave;

  SettingsSnapshot get snapshot => _snapshot;
  bool get isLoaded => _ready.isCompleted;
  Future<void> get ready => _ready.future;

  Future<void> load() async {
    if (_ready.isCompleted) return;
    try {
      final raw = await _persistence.load();
      if (raw != null) {
        final doc = SettingsDocument.fromJson(raw);
        _snapshot = SettingsSnapshot(
          values: Map.unmodifiable(doc.values),
          managed: _snapshot.managed,
          revision: _snapshot.revision + 1,
        );
      }
    } on Object catch (e) {
      // A broken document never blocks launch; defaults apply.
      debugPrint('settings: load failed: $e');
    }
    _ready.complete();
    notifyListeners();
  }

  T get<T extends Object>(SettingKey<T> key) => _snapshot.get(key);

  bool isManaged(SettingKey<Object> key) => _snapshot.isManaged(key);

  void set<T extends Object>(SettingKey<T> key, T value) {
    if (isManaged(key)) throw ManagedSettingException(key.id);
    final next = Map<String, Object?>.of(_snapshot.values);
    final encoded = key.encode(value);
    if (jsonEncode(encoded) == jsonEncode(key.encode(key.defaultValue))) {
      next.remove(key.id);
    } else {
      next[key.id] = encoded;
    }
    _replace(next);
  }

  void reset(SettingKey<Object> key) {
    if (!_snapshot.values.containsKey(key.id)) return;
    _replace(Map.of(_snapshot.values)..remove(key.id));
  }

  /// "Reset section" (docs/06 §3.5): clears every user value under
  /// `<section>.`. Managed values stay.
  void resetSection(String section) {
    final prefix = '$section.';
    _replace(
      Map.of(_snapshot.values)..removeWhere((k, _) => k.startsWith(prefix)),
    );
  }

  void resetAll() => _replace({});

  /// Applies the managed-configuration overlay (B2B-001). Lane C5 maps the
  /// platform's managed config to setting ids and calls this on start and on
  /// every change.
  void applyManaged(Map<String, Object?> managed) {
    _snapshot = SettingsSnapshot(
      values: _snapshot.values,
      managed: Map.unmodifiable(managed),
      revision: _snapshot.revision + 1,
    );
    notifyListeners();
  }

  /// Settings as a JSON document. Window and last-mode state (`shell.*`)
  /// stays on the device.
  String exportJson({DateTime? now}) {
    final values = Map<String, Object?>.of(_snapshot.values)
      ..removeWhere((k, _) => k.startsWith('shell.'));
    final doc = SettingsDocument(
      values: values,
      exportedAt: (now ?? DateTime.now()).toUtc(),
    );
    return const JsonEncoder.withIndent('  ')
        .convert({'format': SettingsDocument.format, ...doc.toJson()});
  }

  /// Imports an exported document. Values for [known] keys are validated
  /// and invalid ones skipped; unknown keys are kept for the lanes that own
  /// them. Managed keys are never overwritten. With [replace] the current
  /// values are cleared first.
  SettingsImportResult importJson(
    String json, {
    Iterable<SettingKey<Object>> known = const [],
    bool replace = true,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const SettingsImportException(SettingsImportError.notJson);
    }
    if (decoded is! Map<String, Object?> ||
        decoded['format'] != SettingsDocument.format) {
      throw const SettingsImportException(SettingsImportError.notSettings);
    }
    final doc = SettingsDocument.fromJson(decoded);
    if (doc.schema > SettingsDocument.currentSchema) {
      throw const SettingsImportException(SettingsImportError.newerSchema);
    }
    final byId = {for (final k in known) k.id: k};
    final next = replace
        ? (Map<String, Object?>.of(_snapshot.values)
            ..removeWhere((k, _) => !k.startsWith('shell.')))
        : Map<String, Object?>.of(_snapshot.values);
    var imported = 0;
    var managed = 0;
    var invalid = 0;
    for (final e in doc.values.entries) {
      if (e.key.startsWith('shell.')) continue;
      if (_snapshot.managed.containsKey(e.key)) {
        managed++;
        continue;
      }
      final key = byId[e.key];
      if (key != null && key.decode(e.value) == null) {
        invalid++;
        continue;
      }
      next[e.key] = e.value;
      imported++;
    }
    _replace(next);
    return SettingsImportResult(
      imported: imported,
      skippedManaged: managed,
      skippedInvalid: invalid,
    );
  }

  void _replace(Map<String, Object?> values) {
    _snapshot = SettingsSnapshot(
      values: Map.unmodifiable(values),
      managed: _snapshot.managed,
      revision: _snapshot.revision + 1,
    );
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    final delay = saveDelay;
    if (delay == null) {
      _pendingSave = _save();
      return;
    }
    _saveTimer = Timer(delay, () => _pendingSave = _save());
  }

  Future<void> _save() async {
    try {
      await _persistence.save(
        SettingsDocument(values: _snapshot.values).toJson(),
      );
    } on Object catch (e) {
      // A full or read-only disk must not crash the app; the next change
      // retries.
      debugPrint('settings: save failed: $e');
    }
  }

  /// Writes pending changes now (app pause, tests).
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _save();
    }
    await _pendingSave;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
