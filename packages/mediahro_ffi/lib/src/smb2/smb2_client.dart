import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/native/posix.dart';
import 'package:mediahro_ffi/src/smb2/smb2_bindings.dart';
import 'package:mediahro_ffi/src/vfs/isolate_file_system.dart';
import 'package:mediahro_ffi/src/vfs/virtual_file.dart';
import 'package:meta/meta.dart';

/// Connection options for an SMB2/3 share (NET-001).
final class SmbOptions {
  const SmbOptions({
    required this.server,
    required this.share,
    this.user,
    this.password,
    this.domain,
    this.port,
    this.guest = false,
    this.version = SmbVersion.any,
    this.encrypt = false,
    this.sign = false,
    this.timeout = const Duration(seconds: 15),
    this.workstation = 'MEDIAHRO',
  });

  final String server;
  final String share;
  final String? user;
  final String? password;
  final String? domain;
  final int? port;

  /// Anonymous/guest access (no credentials).
  final bool guest;
  final SmbVersion version;

  /// SMB3 encryption (seal) for the whole session.
  final bool encrypt;

  /// Require message signing.
  final bool sign;
  final Duration timeout;
  final String workstation;
}

enum SmbVersion {
  any(0),
  smb2(2),
  smb3(3),
  smb2_02(0x0202),
  smb2_10(0x0210),
  smb3_0(0x0300),
  smb3_02(0x0302),
  smb3_11(0x0311);

  const SmbVersion(this.wire);

  final int wire;
}

// enum smb2_sec in libsmb2-private.h (not in the public headers).
const int _secUndefined = 0;
const int _secNtlmssp = 1;

/// Blocking libsmb2 client; runs on its worker isolate only.
final class Smb2SyncFileSystem implements SyncFileSystem {
  Smb2SyncFileSystem(this.options, {Smb2Bindings? bindings})
    : _b = bindings ?? Smb2Bindings(NativeLibraries.open(NativeLibrary.smb2)) {
    if (!options.guest) {
      _ctx = _connect(options.user, options.password ?? '');
    } else {
      // Guest the way Windows and macOS do it: user "guest" with an empty
      // password, which "map to guest = Bad User" servers turn into a guest
      // session. Where that is refused, fall back to a NULL session
      // (anonymous NTLMSSP, sent by libsmb2 only when the password is NULL).
      try {
        _ctx = _connect('guest', '');
      } on VirtualFileException catch (e) {
        if (e.error != VirtualFileError.authenticationRequired &&
            e.error != VirtualFileError.closed &&
            e.error != VirtualFileError.unreachable) {
          rethrow;
        }
        _ctx = _connect('guest', null);
      }
    }
    _maxRead = _b.smb2_get_max_read_size(_ctx).clamp(64 * 1024, 8 << 20);
    _maxWrite = _b.smb2_get_max_write_size(_ctx).clamp(64 * 1024, 8 << 20);
  }

  /// A fresh, connected context; destroyed and mapped to a
  /// [VirtualFileException] when the connect fails. A null [password]
  /// makes libsmb2 send an anonymous (NULL session) NTLMSSP.
  ffi.Pointer<smb2_context> _connect(String? user, String? password) {
    final ctx = _b.smb2_init_context();
    if (ctx == ffi.nullptr) {
      throw VirtualFileException(
        VirtualFileError.io,
        _uri(''),
        'smb2_init_context failed',
      );
    }
    return using((a) {
      _b.smb2_set_timeout(ctx, options.timeout.inSeconds);
      _b.smb2_set_version(
        ctx,
        smb2_negotiate_version.fromValue(options.version.wire),
      );
      _b.smb2_set_workstation(
        ctx,
        options.workstation.toNativeUtf8(allocator: a).cast(),
      );
      if (options.encrypt) _b.smb2_set_seal(ctx, 1);
      if (options.sign || options.encrypt) {
        _b
          ..smb2_set_sign(ctx, 1)
          ..smb2_set_security_mode(ctx, SMB2_NEGOTIATE_SIGNING_REQUIRED);
      }
      _b.smb2_set_authentication(
        ctx,
        user == null ? _secUndefined : _secNtlmssp,
      );
      if (options.domain != null) {
        _b.smb2_set_domain(
          ctx,
          options.domain!.toNativeUtf8(allocator: a).cast(),
        );
      }
      if (user != null) {
        _b.smb2_set_user(ctx, user.toNativeUtf8(allocator: a).cast());
      }
      if (password != null) {
        _b.smb2_set_password(ctx, password.toNativeUtf8(allocator: a).cast());
      }
      final server = options.port == null
          ? options.server
          : '${options.server}:${options.port}';
      final rc = _b.smb2_connect_share(
        ctx,
        server.toNativeUtf8(allocator: a).cast(),
        options.share.toNativeUtf8(allocator: a).cast(),
        user == null ? ffi.nullptr : user.toNativeUtf8(allocator: a).cast(),
      );
      if (rc < 0) {
        final err = _b.smb2_get_error(ctx).cast<Utf8>().toDartString();
        // A fresh context: its NT status is this connect's. libsmb2 turns
        // NT statuses into errno lossily (LOGON_FAILURE is not EACCES), so
        // map the status itself first.
        final nt = _b.smb2_get_nterror(ctx) & 0xffffffff;
        _b.smb2_destroy_context(ctx);
        throw VirtualFileException(
          smbNtStatusError(nt, connect: true) ?? _map(rc, connect: true),
          _uri(''),
          err,
        );
      }
      return ctx;
    });
  }

  final SmbOptions options;
  final Smb2Bindings _b;
  late final ffi.Pointer<smb2_context> _ctx;
  late final int _maxRead;
  late final int _maxWrite;
  final _handles = <int, (ffi.Pointer<smb2fh>, int?)>{};
  int _next = 1;

  /// The negotiated dialect, e.g. 0x0311 (connection-health detail).
  int get dialect => _b.smb2_get_dialect(_ctx);

  Uri _uri(String path) => Uri(
    scheme: 'smb',
    host: options.server,
    pathSegments: [
      options.share,
      ...path.split('/').where((s) => s.isNotEmpty),
    ],
  );

  String _error() => _b.smb2_get_error(_ctx).cast<Utf8>().toDartString();

  @override
  List<VirtualEntry> list(String path) => using((a) {
    final dir = _b.smb2_opendir(_ctx, path.toNativeUtf8(allocator: a).cast());
    if (dir == ffi.nullptr) {
      throw VirtualFileException(_mapMessage(_error()), _uri(path), _error());
    }
    final out = <VirtualEntry>[];
    try {
      while (true) {
        final ent = _b.smb2_readdir(_ctx, dir);
        if (ent == ffi.nullptr) break;
        final name = ent.ref.name.cast<Utf8>().toDartString();
        if (name == '.' || name == '..') continue;
        final st = ent.ref.st;
        final isDir = st.smb2_type == SMB2_TYPE_DIRECTORY;
        final child = path.isEmpty ? name : '$path/$name';
        out.add(
          VirtualEntry(
            uri: _uriEntry(child, directory: isDir),
            name: name,
            isDirectory: isDir,
            size: isDir ? null : st.smb2_size,
            modified: DateTime.fromMillisecondsSinceEpoch(
              st.smb2_mtime * 1000,
              isUtc: true,
            ),
          ),
        );
      }
    } finally {
      _b.smb2_closedir(_ctx, dir);
    }
    return out;
  });

  Uri _uriEntry(String path, {required bool directory}) {
    final u = _uri(path);
    return directory ? u.replace(pathSegments: [...u.pathSegments, '']) : u;
  }

  @override
  VirtualEntry stat(String path) => using((a) {
    final st = a<smb2_stat_64>();
    final rc = _b.smb2_stat(_ctx, path.toNativeUtf8(allocator: a).cast(), st);
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(path), _error());
    final isDir = st.ref.smb2_type == SMB2_TYPE_DIRECTORY;
    return VirtualEntry(
      uri: _uriEntry(path, directory: isDir),
      name: path.split('/').last,
      isDirectory: isDir,
      size: isDir ? null : st.ref.smb2_size,
      modified: DateTime.fromMillisecondsSinceEpoch(
        st.ref.smb2_mtime * 1000,
        isUtc: true,
      ),
    );
  });

  @override
  int open(String path, {bool write = false, bool create = false}) => using((
    a,
  ) {
    final flags = write
        ? PosixOpenFlags.current.writeOnly |
              (create
                  ? PosixOpenFlags.current.create |
                        PosixOpenFlags.current.truncate
                  : 0)
        : PosixOpenFlags.current.readOnly;
    final fh = _b.smb2_open(
      _ctx,
      path.toNativeUtf8(allocator: a).cast(),
      flags,
    );
    if (fh == ffi.nullptr) {
      throw VirtualFileException(_mapMessage(_error()), _uri(path), _error());
    }
    int? size;
    if (!write) {
      final st = a<smb2_stat_64>();
      if (_b.smb2_fstat(_ctx, fh, st) >= 0) size = st.ref.smb2_size;
    }
    final id = _next++;
    _handles[id] = (fh, size);
    return id;
  });

  @override
  int? length(int handle) => _handles[handle]?.$2;

  @override
  Uint8List read(int handle, int offset, int length) {
    final (fh, size) = _fh(handle);
    var want = length;
    if (size != null) {
      if (offset >= size) return Uint8List(0);
      if (offset + want > size) want = size - offset;
    }
    final out = Uint8List(want);
    final buf = calloc<ffi.Uint8>(_maxRead);
    try {
      var got = 0;
      while (got < want) {
        final n = (want - got).clamp(0, _maxRead);
        final rc = _b.smb2_pread(_ctx, fh, buf, n, offset + got);
        if (rc < 0) {
          throw VirtualFileException(
            _map(rc),
            Uri(scheme: 'smb', host: options.server),
            _error(),
          );
        }
        if (rc == 0) break;
        out.setRange(got, got + rc, buf.asTypedList(rc));
        got += rc;
      }
      return got == want ? out : Uint8List.sublistView(out, 0, got);
    } finally {
      calloc.free(buf);
    }
  }

  @override
  void write(int handle, int offset, List<int> bytes) {
    final (fh, _) = _fh(handle);
    final buf = calloc<ffi.Uint8>(_maxWrite);
    try {
      var done = 0;
      while (done < bytes.length) {
        final n = (bytes.length - done).clamp(0, _maxWrite);
        buf.asTypedList(n).setRange(0, n, bytes, done);
        final rc = _b.smb2_pwrite(_ctx, fh, buf, n, offset + done);
        if (rc < 0) {
          throw VirtualFileException(
            _map(rc),
            Uri(scheme: 'smb', host: options.server),
            _error(),
          );
        }
        done += rc;
      }
    } finally {
      calloc.free(buf);
    }
  }

  @override
  void close(int handle) {
    final h = _handles.remove(handle);
    if (h != null) _b.smb2_close(_ctx, h.$1);
  }

  @override
  void mkdir(String path) => _pathOp(path, _b.smb2_mkdir);

  @override
  void unlink(String path) => _pathOp(path, _b.smb2_unlink);

  @override
  void rmdir(String path) => _pathOp(path, _b.smb2_rmdir);

  @override
  void rename(String from, String to) => using((a) {
    final rc = _b.smb2_rename(
      _ctx,
      from.toNativeUtf8(allocator: a).cast(),
      to.toNativeUtf8(allocator: a).cast(),
    );
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(from), _error());
  });

  /// Round-trip used by connection health (NET-019).
  int echo() => _b.smb2_echo(_ctx);

  @override
  void dispose() {
    for (final h in _handles.values) {
      _b.smb2_close(_ctx, h.$1);
    }
    _handles.clear();
    _b
      ..smb2_disconnect_share(_ctx)
      ..smb2_destroy_context(_ctx);
  }

  void _pathOp(
    String path,
    int Function(ffi.Pointer<smb2_context>, ffi.Pointer<ffi.Char>) op,
  ) => using((a) {
    final rc = op(_ctx, path.toNativeUtf8(allocator: a).cast());
    if (rc < 0) throw VirtualFileException(_map(rc), _uri(path), _error());
  });

  (ffi.Pointer<smb2fh>, int?) _fh(int handle) =>
      _handles[handle] ??
      (throw VirtualFileException(VirtualFileError.closed, _uri('')));

  static VirtualFileError _map(int rc, {bool connect = false}) {
    final e = PosixErrno.current;
    final errno = -rc;
    if (errno == e.noent) return VirtualFileError.notFound;
    if (errno == e.acces || errno == e.perm) {
      return connect
          ? VirtualFileError.authenticationRequired
          : VirtualFileError.permissionDenied;
    }
    if (errno == e.exist || errno == e.notempty) {
      return VirtualFileError.alreadyExists;
    }
    if (errno == e.nospc) return VirtualFileError.noSpace;
    if (errno == e.timedout) return VirtualFileError.timeout;
    if (errno == e.connrefused ||
        errno == e.hostunreach ||
        errno == e.netunreach) {
      return VirtualFileError.unreachable;
    }
    return connect ? VirtualFileError.unreachable : VirtualFileError.io;
  }

  /// libsmb2 open/opendir report failures only through the error string.
  static VirtualFileError _mapMessage(String m) {
    final s = m.toUpperCase();
    if (s.contains('OBJECT_NAME_NOT_FOUND') ||
        s.contains('OBJECT_PATH_NOT_FOUND') ||
        s.contains('NO_SUCH_FILE')) {
      return VirtualFileError.notFound;
    }
    if (s.contains('ACCESS_DENIED')) return VirtualFileError.permissionDenied;
    if (s.contains('LOGON_FAILURE')) {
      return VirtualFileError.authenticationRequired;
    }
    if (s.contains('OBJECT_NAME_COLLISION')) {
      return VirtualFileError.alreadyExists;
    }
    if (s.contains('DISK_FULL')) return VirtualFileError.noSpace;
    return VirtualFileError.io;
  }
}

/// NT statuses that mean the credentials (or the account) were refused.
const Set<int> _ntLogonRefused = {
  0xC000006D, // LOGON_FAILURE
  0xC000006A, // WRONG_PASSWORD
  0xC0000064, // NO_SUCH_USER
  0xC000006E, // ACCOUNT_RESTRICTION
  0xC000006F, // INVALID_LOGON_HOURS
  0xC0000070, // INVALID_WORKSTATION
  0xC0000071, // PASSWORD_EXPIRED
  0xC0000072, // ACCOUNT_DISABLED
  0xC0000193, // ACCOUNT_EXPIRED
  0xC0000224, // PASSWORD_MUST_CHANGE
  0xC0000234, // ACCOUNT_LOCKED_OUT
  0xC000015B, // LOGON_TYPE_NOT_GRANTED
};

/// [VirtualFileError] for an SMB NT status, or null when it says nothing
/// more than the errno would. [connect]: the status came from negotiate,
/// session setup or tree connect, where ACCESS_DENIED means "not with
/// these credentials".
@visibleForTesting
VirtualFileError? smbNtStatusError(int status, {bool connect = false}) {
  if (_ntLogonRefused.contains(status)) {
    return VirtualFileError.authenticationRequired;
  }
  return switch (status) {
    0xC0000022 => // ACCESS_DENIED
      connect
          ? VirtualFileError.authenticationRequired
          : VirtualFileError.permissionDenied,
    0xC00000CC || // BAD_NETWORK_NAME (no such share)
    0xC0000034 || // OBJECT_NAME_NOT_FOUND
    0xC000003A || // OBJECT_PATH_NOT_FOUND
    0xC000000F => VirtualFileError.notFound, // NO_SUCH_FILE
    0xC0000035 => VirtualFileError.alreadyExists, // OBJECT_NAME_COLLISION
    0xC0000103 => VirtualFileError.notADirectory, // NOT_A_DIRECTORY
    0xC00000BA => VirtualFileError.isADirectory, // FILE_IS_A_DIRECTORY
    0xC000007F => VirtualFileError.noSpace, // DISK_FULL
    _ => null,
  };
}

/// `smb://[domain;user@]server[:port]/share/path` as an [IsolateFileSystem].
IsolateFileSystem smbFileSystem(Uri root, SmbOptions options) =>
    IsolateFileSystem(
      root: root,
      schemes: const {'smb'},
      debugName: 'mediahro-smb:${options.server}',
      factory: () => Smb2SyncFileSystem(options),
    );

/// Splits `smb://DOMAIN;user@host:445/share/dir` into options (credentials
/// in the URI are only used when no stored credential exists).
SmbOptions smbOptionsFromUri(
  Uri uri, {
  String? user,
  String? password,
  bool guest = false,
}) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) {
    throw ArgumentError.value(uri, 'uri', 'needs a share: smb://host/share');
  }
  String? domain;
  var u = user;
  if (u == null && uri.userInfo.isNotEmpty) {
    final info = Uri.decodeComponent(uri.userInfo.split(':').first);
    final semi = info.indexOf(';');
    if (semi > 0) {
      domain = info.substring(0, semi);
      u = info.substring(semi + 1);
    } else {
      u = info;
    }
  }
  return SmbOptions(
    server: uri.host,
    share: segs.first,
    user: u,
    password: password,
    domain: domain,
    port: uri.hasPort ? uri.port : null,
    guest: guest,
  );
}

/// Whether libsmb2 can be loaded in this build (feature detection).
bool get smb2Available =>
    !Platform.environment.containsKey('MEDIAHRO_NO_NATIVE') &&
    NativeLibraries.isAvailable(NativeLibrary.smb2);
