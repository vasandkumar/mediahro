import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// SFTP sources (NET-004) over the platform's own SSH stack (ADR-017):
/// sshj/JCA on Android, SwiftNIO SSH on Apple, libssh2 + WinCNG on Windows,
/// all behind [SftpFacade]. Secrets reach the platform only as
/// SecureStorage references ([SftpEndpoint]).
///
/// Host keys are trust-on-first-use: a first connection, or a key that
/// differs from the confirmed one, fails with
/// [VirtualFileError.untrustedCertificate] carrying the new fingerprint so
/// the user can compare it (docs/05 §9). Nothing is listed or read before.
/// Where the raw SFTP secret of a source lives in SecureStorage: the value
/// the platform reads through [SftpEndpoint] references.
extension type const SftpSecretRefs(String credentialKey) {
  String get password => '$credentialKey/password';
  String get privateKey => '$credentialKey/privateKey';
  String get keyPassphrase => '$credentialKey/keyPassphrase';
}

final class SftpFileSystem implements MutableFileSystem {
  SftpFileSystem(this.facade, this.endpoint);

  final SftpFacade facade;
  final SftpEndpoint endpoint;
  SftpSession? _session;
  Future<SftpSession>? _connecting;

  @override
  Set<String> get schemes => const {'sftp'};

  @override
  Set<VirtualFsCapability> get capabilities => const {
    VirtualFsCapability.list,
    VirtualFsCapability.write,
    VirtualFsCapability.rename,
    VirtualFsCapability.delete,
  };

  Future<SftpSession> _connect(Uri uri) {
    if (_session case final s?) return Future.value(s);
    return _connecting ??= _open(uri).whenComplete(() => _connecting = null);
  }

  Future<SftpSession> _open(Uri uri) async {
    final s = await facade.connect(endpoint);
    final key = s.hostKeySha256;
    if (endpoint.knownHostKeySha256 != key) {
      // First contact or a changed host key: never proceed unconfirmed.
      await _quietly(s.close);
      throw VirtualFileException(
        VirtualFileError.untrustedCertificate,
        uri,
        key,
      );
    }
    return _session = s;
  }

  Future<T> _run<T>(Uri uri, Future<T> Function(SftpSession s) op) async {
    try {
      return await op(await _connect(uri));
    } on VirtualFileException {
      rethrow;
    } on UntrustedCertificate catch (e) {
      throw VirtualFileException(
        VirtualFileError.untrustedCertificate,
        uri,
        e.sha256,
      );
    } on PlatformCapabilityUnavailable catch (e) {
      throw VirtualFileException(VirtualFileError.unsupported, uri, '$e');
    } on TimeoutException catch (e) {
      await _drop();
      throw VirtualFileException(VirtualFileError.timeout, uri, '$e');
    } on SocketException catch (e) {
      await _drop();
      throw VirtualFileException(VirtualFileError.unreachable, uri, '$e');
    } on Exception catch (e) {
      throw VirtualFileException(VirtualFileError.io, uri, '$e');
    }
  }

  Future<void> _drop() async {
    final s = _session;
    _session = null;
    if (s != null) await _quietly(s.close);
  }

  static Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } on Object catch (_) {
      // already gone
    }
  }

  /// Server path of [uri] (`sftp://host/home/me/x` → `/home/me/x`).
  static String path(Uri uri) {
    final p = Uri.decodeComponent(uri.path);
    if (p.contains('\x00')) {
      throw VirtualFileException(VirtualFileError.notFound, uri, 'bad path');
    }
    if (p.length > 1 && p.endsWith('/')) return p.substring(0, p.length - 1);
    return p.isEmpty ? '/' : p;
  }

  static Uri _child(Uri dir, String name) => dir.replace(
    pathSegments: [...dir.pathSegments.where((s) => s.isNotEmpty), name],
  );

  static Uri _parent(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return uri.replace(
      pathSegments: segs.isEmpty ? const [] : segs.sublist(0, segs.length - 1),
    );
  }

  static String _name(String path) {
    final p = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  VirtualEntry _entry(Uri uri, SftpEntry e) => VirtualEntry(
    uri: uri,
    name: _name(e.path).isEmpty ? '/' : _name(e.path),
    isDirectory: e.isDirectory,
    size: e.isDirectory ? null : e.size,
    modified: e.modified,
  );

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final entries = await _run(directory, (s) => s.list(path(directory)));
    for (final e in entries) {
      final name = _name(e.path);
      if (name.isEmpty || name == '.' || name == '..') continue;
      yield _entry(_child(directory, name), e);
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async =>
      _entry(uri, await _run(uri, (s) => s.stat(path(uri))));

  @override
  Future<VirtualFile> open(Uri uri) async {
    final e = await stat(uri);
    if (e.isDirectory) {
      throw VirtualFileException(
        VirtualFileError.notFound,
        uri,
        'is a directory',
      );
    }
    return _SftpFile(this, uri, e.size);
  }

  Future<bool> _exists(SftpSession s, String p) async {
    try {
      await s.stat(p);
      return true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<Uri> rename(Uri uri, String newName) async {
    if (newName.isEmpty ||
        newName == '.' ||
        newName == '..' ||
        newName.contains('/')) {
      throw VirtualFileException(VirtualFileError.notFound, uri, 'bad name');
    }
    return await _renameTo(uri, _child(_parent(uri), newName));
  }

  @override
  Future<Uri> move(Uri uri, Uri directory) => _renameTo(
    uri,
    _child(directory, uri.pathSegments.where((s) => s.isNotEmpty).last),
  );

  Future<Uri> _renameTo(Uri from, Uri to) => _run(from, (s) async {
    if (await _exists(s, path(to))) {
      throw VirtualFileException(VirtualFileError.alreadyExists, to);
    }
    await s.rename(path(from), path(to));
    return to;
  });

  @override
  Future<void> delete(Uri uri, {bool recursive = false}) =>
      _run(uri, (s) => _delete(s, uri, recursive: recursive));

  Future<void> _delete(
    SftpSession s,
    Uri uri, {
    required bool recursive,
  }) async {
    final e = await s.stat(path(uri));
    if (e.isDirectory && recursive) {
      for (final c in await s.list(path(uri))) {
        final name = _name(c.path);
        if (name.isEmpty || name == '.' || name == '..') continue;
        await _delete(s, _child(uri, name), recursive: true);
      }
    }
    await s.delete(path(uri));
  }

  static String _checkName(String name, Uri uri) {
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
      throw VirtualFileException(VirtualFileError.notFound, uri, 'bad name');
    }
    return name;
  }

  @override
  Future<Uri> createDirectory(Uri parent, String name) async {
    final uri = _child(parent, _checkName(name, parent));
    return await _run(uri, (s) async {
      if (await _exists(s, path(uri))) {
        throw VirtualFileException(VirtualFileError.alreadyExists, uri);
      }
      await s.mkdir(path(uri));
      return uri;
    });
  }

  /// A new file; an existing name is refused (copy/move never overwrite).
  @override
  Future<VirtualFileWriter> create(Uri uri) => _run(uri, (s) async {
    if (await _exists(s, path(uri))) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    return _SftpWriter(this, uri, await s.openWrite(path(uri)));
  });

  Future<void> close() => _drop();
}

final class _SftpFile implements VirtualFile {
  _SftpFile(this._fs, this.uri, this._length);

  final SftpFileSystem _fs;
  @override
  final Uri uri;
  final int? _length;
  bool _closed = false;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => _length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    final size = _length;
    if (length <= 0 || (size != null && offset >= size)) return Uint8List(0);
    final n = size == null || offset + length <= size ? length : size - offset;
    return await _fs._run(
      uri,
      (s) => s.read(SftpFileSystem.path(uri), offset, n),
    );
  }

  @override
  Future<void> close() async => _closed = true;
}

final class _SftpWriter implements VirtualFileWriter {
  _SftpWriter(this._fs, this.uri, this._sink);

  final SftpFileSystem _fs;
  @override
  final Uri uri;
  final SftpWriteSink _sink;
  bool _ended = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (_ended) throw VirtualFileException(VirtualFileError.closed, uri);
    await _fs._run(
      uri,
      (_) =>
          _sink.write(bytes is Uint8List ? bytes : Uint8List.fromList(bytes)),
    );
  }

  @override
  Future<void> close() async {
    if (_ended) return;
    _ended = true;
    await _fs._run(uri, (_) => _sink.close());
  }

  @override
  Future<void> abort() async {
    if (_ended) return;
    _ended = true;
    try {
      await _sink.abort();
    } on Object catch (_) {
      // the platform removes the partial file; nothing else to do
    }
  }
}
