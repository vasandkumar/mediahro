import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_ffi/src/curl/curl_bindings.dart';
import 'package:mediahro_ffi/src/curl/list_parser.dart';
import 'package:mediahro_ffi/src/native/native_library.dart';
import 'package:mediahro_ffi/src/vfs/isolate_file_system.dart';
import 'package:mediahro_ffi/src/vfs/virtual_file.dart';

enum CurlProtocol {
  /// Plain FTP.
  ftp('ftp'),

  /// Explicit FTPS (AUTH TLS on port 21).
  ftpes('ftp'),

  /// Implicit FTPS (port 990).
  ftps('ftps'),
  sftp('sftp');

  const CurlProtocol(this.urlScheme);

  final String urlScheme;
}

/// Options for an FTP/FTPS/SFTP source (NET-004).
final class CurlOptions {
  const CurlOptions({
    required this.protocol,
    required this.host,
    this.port,
    this.rootPath = '/',
    this.user,
    this.password,
    this.privateKeyPem,
    this.keyPassphrase,
    this.hostKeySha256,
    this.allowUntrustedTls = false,
    this.keyDirectory,
    this.timeout = const Duration(seconds: 20),
  });

  final CurlProtocol protocol;
  final String host;
  final int? port;

  /// Server path of the source root (`/` or `/srv/media`).
  final String rootPath;
  final String? user;
  final String? password;

  /// SFTP key authentication (PEM/OpenSSH format).
  final String? privateKeyPem;
  final String? keyPassphrase;

  /// Pinned SFTP host key: base64 of the SHA-256 of the key blob (what
  /// `ssh-keygen -l` shows after `SHA256:`, with `=` padding). Null on the first connection: the
  /// host key is reported with [VirtualFileError.untrustedCertificate]
  /// for the user to confirm (trust on first use).
  final String? hostKeySha256;

  /// FTPS with a self-signed certificate the user accepted.
  final bool allowUntrustedTls;

  /// App-private directory for the temporary key file (libcurl reads SFTP
  /// keys from a file; it is deleted on [SyncFileSystem.dispose]).
  final String? keyDirectory;
  final Duration timeout;
}

const int _useSslAll = 3;

/// Blocking libcurl client for FTP, FTPS and SFTP; runs on its worker
/// isolate only. HTTP is never enabled on these handles (ADR-014).
final class CurlSyncFileSystem implements SyncFileSystem {
  CurlSyncFileSystem(this.options, {CurlBindings? bindings})
    : _b = bindings ?? CurlBindings(NativeLibraries.open(NativeLibrary.curl)) {
    if (!_globalInit) {
      _b.curl_global_init(CURL_GLOBAL_DEFAULT);
      _globalInit = true;
    }
    _h = _b.curl_easy_init();
    if (_h == ffi.nullptr) {
      throw VirtualFileException(
        VirtualFileError.io,
        _url(''),
        'curl_easy_init failed',
      );
    }
    _writeCb = ffi.NativeCallable<_WriteFn>.isolateLocal(
      _onWrite,
      exceptionalReturn: 0,
    );
    _readCb = ffi.NativeCallable<_WriteFn>.isolateLocal(
      _onRead,
      exceptionalReturn: CURL_READFUNC_ABORT,
    );
    _hostKeyCb = ffi.NativeCallable<_HostKeyFn>.isolateLocal(
      _onHostKey,
      exceptionalReturn: 1,
    );
    final pem = options.privateKeyPem;
    if (pem != null) {
      final dir = Directory(options.keyDirectory ?? Directory.systemTemp.path);
      final f = File(
        '${dir.path}${Platform.pathSeparator}.mediahro-key-${DateTime.now().microsecondsSinceEpoch}',
      )..writeAsStringSync(pem, flush: true);
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['600', f.path]);
      }
      _keyFile = f;
    }
    // Verify the connection and credentials now (test-before-save).
    list('');
  }

  final CurlOptions options;
  final CurlBindings _b;
  late final ffi.Pointer<CURL> _h;
  late final ffi.NativeCallable<_WriteFn> _writeCb;
  late final ffi.NativeCallable<_WriteFn> _readCb;
  late final ffi.NativeCallable<_HostKeyFn> _hostKeyCb;
  File? _keyFile;
  static bool _globalInit = false;

  BytesBuilder? _sink;
  int _sinkLimit = 0;
  Uint8List _upload = Uint8List(0);
  int _uploadPos = 0;
  String? _seenHostKey;
  final _handles = <int, (String, int?)>{};
  final _listCache = <String, (DateTime, List<VirtualEntry>)>{};
  int _next = 1;

  /// The SFTP host key fingerprint seen on the last connection attempt.
  String? get seenHostKey => _seenHostKey;

  Uri _url(String path, {bool directory = false}) {
    final base = options.rootPath.split('/').where((s) => s.isNotEmpty);
    final segs = [...base, ...path.split('/').where((s) => s.isNotEmpty)];
    return Uri(
      scheme: options.protocol.urlScheme,
      host: options.host,
      port: options.port,
      pathSegments: [...segs, if (directory || segs.isEmpty) ''],
    );
  }

  /// Absolute server path for quote commands.
  String _serverPath(String path) {
    final segs = [
      ...options.rootPath.split('/').where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
    ];
    return '/${segs.join('/')}';
  }

  void _setup(Arena a, Uri url) {
    final b = _b..curl_easy_reset(_h);
    String ptr(CURLoption o, String v) {
      b.curl_easy_setopt_ptr(_h, o, v.toNativeUtf8(allocator: a).cast());
      return v;
    }

    void long(CURLoption o, int v) => b.curl_easy_setopt_long(_h, o, v);
    ptr(CURLoption.CURLOPT_URL, url.toString());
    final protos = options.protocol == CurlProtocol.sftp ? 'sftp' : 'ftp,ftps';
    ptr(CURLoption.CURLOPT_PROTOCOLS_STR, protos);
    ptr(CURLoption.CURLOPT_REDIR_PROTOCOLS_STR, protos);
    long(CURLoption.CURLOPT_NOSIGNAL, 1);
    long(CURLoption.CURLOPT_CONNECTTIMEOUT_MS, options.timeout.inMilliseconds);
    long(CURLoption.CURLOPT_LOW_SPEED_LIMIT, 1);
    long(CURLoption.CURLOPT_LOW_SPEED_TIME, options.timeout.inSeconds);
    b.curl_easy_setopt_ptr(
      _h,
      CURLoption.CURLOPT_WRITEFUNCTION,
      _writeCb.nativeFunction.cast(),
    );
    if (options.user != null) ptr(CURLoption.CURLOPT_USERNAME, options.user!);
    if (options.password != null) {
      ptr(CURLoption.CURLOPT_PASSWORD, options.password!);
    }
    switch (options.protocol) {
      case CurlProtocol.ftpes || CurlProtocol.ftps:
        long(CURLoption.CURLOPT_USE_SSL, _useSslAll);
        if (options.allowUntrustedTls) {
          long(CURLoption.CURLOPT_SSL_VERIFYPEER, 0);
          long(CURLoption.CURLOPT_SSL_VERIFYHOST, 0);
        }
      case CurlProtocol.ftp:
        break;
      case CurlProtocol.sftp:
        final key = _keyFile;
        if (key != null) {
          long(CURLoption.CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_PUBLICKEY);
          ptr(CURLoption.CURLOPT_SSH_PRIVATE_KEYFILE, key.path);
          if (options.keyPassphrase != null) {
            ptr(CURLoption.CURLOPT_KEYPASSWD, options.keyPassphrase!);
          }
        } else {
          long(
            CURLoption.CURLOPT_SSH_AUTH_TYPES,
            CURLSSH_AUTH_PASSWORD | CURLSSH_AUTH_KEYBOARD,
          );
        }
        final pin = options.hostKeySha256;
        if (pin != null) {
          ptr(CURLoption.CURLOPT_SSH_HOST_PUBLIC_KEY_SHA256, pin);
        } else {
          b.curl_easy_setopt_ptr(
            _h,
            CURLoption.CURLOPT_SSH_HOSTKEYFUNCTION,
            _hostKeyCb.nativeFunction.cast(),
          );
        }
    }
    long(CURLoption.CURLOPT_FTP_FILEMETHOD, 3); // CURLFTPMETHOD_SINGLECWD
  }

  void _perform(Uri url, String what) {
    final rc = _b.curl_easy_perform(_h);
    if (rc == CURLcode.CURLE_OK) return;
    final msg = _b.curl_easy_strerror(rc).cast<Utf8>().toDartString();
    final hostKey = _seenHostKey;
    if (options.protocol == CurlProtocol.sftp &&
        options.hostKeySha256 == null &&
        hostKey != null) {
      throw VirtualFileException(
        VirtualFileError.untrustedCertificate,
        url,
        hostKey,
      );
    }
    throw VirtualFileException(_map(rc), url, '$what: $msg');
  }

  int _onWrite(
    ffi.Pointer<ffi.Char> data,
    int size,
    int n,
    ffi.Pointer<ffi.Void> _,
  ) {
    final len = size * n;
    final sink = _sink;
    if (sink != null) {
      final room = _sinkLimit - sink.length;
      final take = len < room ? len : room;
      if (take > 0) sink.add(data.cast<ffi.Uint8>().asTypedList(take));
      // Returning less than len stops the transfer once we have enough.
      if (take < len) return take == 0 && room <= 0 ? 0 : take;
    }
    return len;
  }

  int _onRead(
    ffi.Pointer<ffi.Char> buf,
    int size,
    int n,
    ffi.Pointer<ffi.Void> _,
  ) {
    final room = size * n;
    final left = _upload.length - _uploadPos;
    final take = left < room ? left : room;
    if (take > 0) {
      buf
          .cast<ffi.Uint8>()
          .asTypedList(take)
          .setRange(0, take, _upload, _uploadPos);
      _uploadPos += take;
    }
    return take;
  }

  int _onHostKey(
    ffi.Pointer<ffi.Void> _,
    int keyType,
    ffi.Pointer<ffi.Char> key,
    int keyLen,
  ) {
    // libcurl passes the raw host key blob; the fingerprint is base64(SHA-256).
    final bytes = Uint8List.fromList(key.cast<ffi.Uint8>().asTypedList(keyLen));
    _seenHostKey = base64.encode(_sha256(bytes));
    // No pin yet: refuse, so the user can confirm the fingerprint first.
    return curl_khmatch.CURLKHMATCH_MISMATCH.value;
  }

  Uint8List _fetch(
    Uri url, {
    String? range,
    int limit = 64 << 20,
    String what = 'read',
  }) => using((a) {
    _setup(a, url);
    if (range != null) {
      _b.curl_easy_setopt_ptr(
        _h,
        CURLoption.CURLOPT_RANGE,
        range.toNativeUtf8(allocator: a).cast(),
      );
    }
    final sink = BytesBuilder(copy: false);
    _sink = sink;
    _sinkLimit = limit;
    try {
      final rc = _b.curl_easy_perform(_h);
      final got = sink.length;
      // Stopping early on purpose reports CURLE_WRITE_ERROR (23).
      if (rc != CURLcode.CURLE_OK &&
          !(rc == CURLcode.CURLE_WRITE_ERROR && got >= limit)) {
        _sink = null;
        final msg = _b.curl_easy_strerror(rc).cast<Utf8>().toDartString();
        final hostKey = _seenHostKey;
        if (options.protocol == CurlProtocol.sftp &&
            options.hostKeySha256 == null &&
            hostKey != null) {
          throw VirtualFileException(
            VirtualFileError.untrustedCertificate,
            url,
            hostKey,
          );
        }
        throw VirtualFileException(_map(rc), url, '$what: $msg');
      }
      return sink.takeBytes();
    } finally {
      _sink = null;
    }
  });

  @override
  List<VirtualEntry> list(String path) {
    final cached = _listCache[path];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 5)) {
      return cached.$2;
    }
    final url = _url(path, directory: true);
    final text = utf8.decode(_fetch(url, what: 'list'), allowMalformed: true);
    final entries = [
      for (final e in parseListing(text))
        VirtualEntry(
          uri: _url(
            path.isEmpty ? e.name : '$path/${e.name}',
            directory: e.isDirectory,
          ),
          name: e.name,
          isDirectory: e.isDirectory,
          size: e.size,
          modified: e.modified,
        ),
    ];
    _listCache[path] = (DateTime.now(), entries);
    return entries;
  }

  @override
  VirtualEntry stat(String path) {
    if (path.isEmpty) {
      return VirtualEntry(
        uri: _url('', directory: true),
        name: '',
        isDirectory: true,
      );
    }
    final i = path.lastIndexOf('/');
    final parent = i < 0 ? '' : path.substring(0, i);
    final name = path.substring(i + 1);
    for (final e in list(parent)) {
      if (e.name == name) return e;
    }
    throw VirtualFileException(VirtualFileError.notFound, _url(path));
  }

  @override
  int open(String path, {bool write = false, bool create = false}) {
    final id = _next++;
    _handles[id] = (path, write ? 0 : stat(path).size);
    if (write) _invalidate(path);
    return id;
  }

  @override
  int? length(int handle) => _handles[handle]?.$2;

  @override
  Uint8List read(int handle, int offset, int length) {
    final (path, size) =
        _handles[handle] ??
        (throw VirtualFileException(VirtualFileError.closed, _url('')));
    var want = length;
    if (size != null) {
      if (offset >= size) return Uint8List(0);
      if (offset + want > size) want = size - offset;
    }
    if (want == 0) return Uint8List(0);
    return _fetch(
      _url(path),
      range: '$offset-${offset + want - 1}',
      limit: want,
    );
  }

  @override
  void write(int handle, int offset, List<int> bytes) {
    final (path, _) =
        _handles[handle] ??
        (throw VirtualFileException(VirtualFileError.closed, _url('')));
    using((a) {
      final url = _url(path);
      _setup(a, url);
      _b
        ..curl_easy_setopt_long(_h, CURLoption.CURLOPT_UPLOAD, 1)
        ..curl_easy_setopt_ptr(
          _h,
          CURLoption.CURLOPT_READFUNCTION,
          _readCb.nativeFunction.cast(),
        )
        ..curl_easy_setopt_off(
          _h,
          CURLoption.CURLOPT_INFILESIZE_LARGE,
          bytes.length,
        );
      // Sequential writes: the first creates/truncates, later ones append.
      if (offset > 0) {
        _b.curl_easy_setopt_long(_h, CURLoption.CURLOPT_APPEND, 1);
      }
      _b.curl_easy_setopt_long(
        _h,
        CURLoption.CURLOPT_FTP_CREATE_MISSING_DIRS,
        0,
      );
      _upload = Uint8List.fromList(bytes);
      _uploadPos = 0;
      try {
        _perform(url, 'upload');
      } finally {
        _upload = Uint8List(0);
      }
    });
  }

  @override
  void close(int handle) => _handles.remove(handle);

  @override
  void mkdir(String path) => _quote(
    path,
    options.protocol == CurlProtocol.sftp
        ? ['mkdir ${_q(_serverPath(path))}']
        : ['MKD ${_serverPath(path)}'],
  );

  @override
  void rmdir(String path) => _quote(
    path,
    options.protocol == CurlProtocol.sftp
        ? ['rmdir ${_q(_serverPath(path))}']
        : ['RMD ${_serverPath(path)}'],
  );

  @override
  void unlink(String path) => _quote(
    path,
    options.protocol == CurlProtocol.sftp
        ? ['rm ${_q(_serverPath(path))}']
        : ['DELE ${_serverPath(path)}'],
  );

  @override
  void rename(String from, String to) => _quote(
    from,
    options.protocol == CurlProtocol.sftp
        ? ['rename ${_q(_serverPath(from))} ${_q(_serverPath(to))}']
        : ['RNFR ${_serverPath(from)}', 'RNTO ${_serverPath(to)}'],
    also: to,
  );

  void _quote(String path, List<String> commands, {String? also}) => using((a) {
    final url = _url('', directory: true);
    _setup(a, url);
    var list = ffi.Pointer<curl_slist>.fromAddress(0);
    for (final c in commands) {
      list = _b.curl_slist_append(list, c.toNativeUtf8(allocator: a).cast());
    }
    try {
      _b
        ..curl_easy_setopt_ptr(_h, CURLoption.CURLOPT_QUOTE, list.cast())
        ..curl_easy_setopt_long(_h, CURLoption.CURLOPT_NOBODY, 1);
      _perform(_url(path), commands.first.split(' ').first);
    } finally {
      _b.curl_slist_free_all(list);
    }
    _invalidate(path);
    if (also != null) _invalidate(also);
  });

  /// SFTP quote arguments with spaces must be double-quoted.
  static String _q(String p) =>
      '"${p.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  void _invalidate(String path) {
    final i = path.lastIndexOf('/');
    _listCache
      ..remove(i < 0 ? '' : path.substring(0, i))
      ..remove(path);
  }

  @override
  void dispose() {
    _b.curl_easy_cleanup(_h);
    _writeCb.close();
    _readCb.close();
    _hostKeyCb.close();
    try {
      _keyFile?.deleteSync();
    } on FileSystemException {
      // Already gone.
    }
  }

  static VirtualFileError _map(CURLcode rc) => switch (rc) {
    CURLcode.CURLE_COULDNT_RESOLVE_HOST ||
    CURLcode.CURLE_COULDNT_CONNECT => VirtualFileError.unreachable,
    CURLcode.CURLE_OPERATION_TIMEDOUT => VirtualFileError.timeout,
    CURLcode.CURLE_LOGIN_DENIED => VirtualFileError.authenticationRequired,
    CURLcode.CURLE_REMOTE_ACCESS_DENIED => VirtualFileError.permissionDenied,
    CURLcode.CURLE_REMOTE_FILE_NOT_FOUND ||
    CURLcode.CURLE_FTP_COULDNT_RETR_FILE => VirtualFileError.notFound,
    CURLcode.CURLE_REMOTE_DISK_FULL => VirtualFileError.noSpace,
    CURLcode.CURLE_REMOTE_FILE_EXISTS => VirtualFileError.alreadyExists,
    CURLcode.CURLE_PEER_FAILED_VERIFICATION =>
      VirtualFileError.untrustedCertificate,
    CURLcode.CURLE_RANGE_ERROR ||
    CURLcode.CURLE_UNSUPPORTED_PROTOCOL => VirtualFileError.unsupported,
    _ => VirtualFileError.io,
  };
}

typedef _WriteFn = ffi.Size Function(
  ffi.Pointer<ffi.Char>,
  ffi.Size,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);
typedef _HostKeyFn = ffi.Int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Int,
  ffi.Pointer<ffi.Char>,
  ffi.Size,
);

/// `ftp://`, `ftps://`, `sftp://` sources as an [IsolateFileSystem].
IsolateFileSystem curlFileSystem(Uri root, CurlOptions options) =>
    IsolateFileSystem(
      root: root,
      schemes: const {'ftp', 'ftps', 'ftpes', 'sftp'},
      debugName: 'mediahro-${options.protocol.name}:${options.host}',
      factory: () => CurlSyncFileSystem(options),
    );

/// SHA-256 (FIPS 180-4) for host key fingerprints; the worker isolate has
/// no package:crypto (mediahro_ffi stays dependency-light).
Uint8List _sha256(Uint8List msg) {
  const k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5, //
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final bitLen = msg.length * 8;
  final padLen = ((msg.length + 9 + 63) ~/ 64) * 64;
  final m = Uint8List(padLen)..setRange(0, msg.length, msg);
  m[msg.length] = 0x80;
  final bd = ByteData.sublistView(m)..setUint64(padLen - 8, bitLen);
  int rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;
  final w = List<int>.filled(64, 0);
  for (var off = 0; off < padLen; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(off + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }
    var a = h[0];
    var b = h[1];
    var c = h[2];
    var d = h[3];
    var e = h[4];
    var f = h[5];
    var g = h[6];
    var hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xFFFFFFFF & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xFFFFFFFF;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xFFFFFFFF;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xFFFFFFFF;
    }
    h[0] = (h[0] + a) & 0xFFFFFFFF;
    h[1] = (h[1] + b) & 0xFFFFFFFF;
    h[2] = (h[2] + c) & 0xFFFFFFFF;
    h[3] = (h[3] + d) & 0xFFFFFFFF;
    h[4] = (h[4] + e) & 0xFFFFFFFF;
    h[5] = (h[5] + f) & 0xFFFFFFFF;
    h[6] = (h[6] + g) & 0xFFFFFFFF;
    h[7] = (h[7] + hh) & 0xFFFFFFFF;
  }
  final out = ByteData(32);
  for (var i = 0; i < 8; i++) {
    out.setUint32(i * 4, h[i]);
  }
  return out.buffer.asUint8List();
}

/// Exposed for tests of the fingerprint helper.
Uint8List sha256ForTesting(Uint8List msg) => _sha256(msg);
