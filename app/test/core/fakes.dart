import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro/platform/security.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// In-memory read-only file system; immutable so it can cross isolates.
final class MemoryFileSystem implements VirtualFileSystem {
  MemoryFileSystem(Map<String, Uint8List> files, {DateTime? modified})
    : _files = Map.unmodifiable(files),
      _modified = modified ?? DateTime.utc(2026);

  /// `relative/path` → bytes.
  final Map<String, Uint8List> _files;
  final DateTime _modified;

  static final Uri root = Uri.parse('mem:///');

  @override
  Set<String> get schemes => const {'mem'};

  @override
  Set<VirtualFsCapability> get capabilities => const {VirtualFsCapability.list};

  static String rel(Uri uri) =>
      uri.pathSegments.where((s) => s.isNotEmpty).join('/');

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final dir = rel(directory);
    final prefix = dir.isEmpty ? '' : '$dir/';
    final seenDirs = <String>{};
    final out = <VirtualEntry>[];
    for (final e in _files.entries) {
      if (!e.key.startsWith(prefix)) continue;
      final rest = e.key.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        out.add(
          VirtualEntry(
            uri: root.replace(pathSegments: e.key.split('/')),
            name: rest,
            isDirectory: false,
            size: e.value.length,
            modified: _modified,
          ),
        );
      } else if (seenDirs.add(rest.substring(0, slash))) {
        final name = rest.substring(0, slash);
        out.add(
          VirtualEntry(
            uri: root.replace(
              pathSegments: [
                ...prefix.split('/').where((s) => s.isNotEmpty),
                name,
                '',
              ],
            ),
            name: name,
            isDirectory: true,
          ),
        );
      }
    }
    if (out.isEmpty && dir.isNotEmpty) {
      throw VirtualFileException(VirtualFileError.notFound, directory);
    }
    for (final e in out) {
      yield e;
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final r = rel(uri);
    final f = _files[r];
    if (f == null) throw VirtualFileException(VirtualFileError.notFound, uri);
    return VirtualEntry(
      uri: uri,
      name: r.split('/').last,
      isDirectory: false,
      size: f.length,
      modified: _modified,
    );
  }

  @override
  Future<VirtualFile> open(Uri uri) async {
    final f = _files[rel(uri)];
    if (f == null) throw VirtualFileException(VirtualFileError.notFound, uri);
    return MemoryFile(uri, f);
  }
}

final class MemoryFile implements VirtualFile {
  MemoryFile(this.uri, this.bytes);

  @override
  final Uri uri;
  final Uint8List bytes;
  bool _closed = false;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    if (offset >= bytes.length) return Uint8List(0);
    final end = offset + length > bytes.length ? bytes.length : offset + length;
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  Future<void> close() async => _closed = true;
}

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

final class FakeSecureStorage implements SecureStorageFacade {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<int>> wrapKey(
    List<int> key, {
    required bool requireBiometry,
  }) async => [for (final b in key) b ^ 0x5a];

  @override
  Future<List<int>> unwrapKey(
    List<int> wrapped, {
    required String reason,
  }) async => [for (final b in wrapped) b ^ 0x5a];
}

final class FakeBiometrics implements BiometricsFacade {
  FakeBiometrics({this.succeed = true});

  bool succeed;
  int prompts = 0;

  @override
  Future<BiometricKind> available() async => BiometricKind.fingerprint;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return succeed;
  }
}
