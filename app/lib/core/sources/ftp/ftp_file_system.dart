import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// FTP, explicit FTPS (AUTH TLS) and implicit FTPS (NET-004) over dart:io
/// sockets and the platform TLS of the Dart runtime.
///
/// This is the Apple fallback: libcurl ≥ 8.15 has no TLS backend on Apple
/// and the mediahro-deps Apple archives ship no libssh2 (docs/05 §2, ADR
/// request in STATUS §6). Other platforms use libcurl through
/// [curlFileSystem]; both implement the same [MutableFileSystem] contract.
enum FtpSecurity { none, explicit, implicit }

final class FtpOptions {
  const FtpOptions({
    required this.host,
    this.port,
    this.security = FtpSecurity.none,
    this.user,
    this.password,
    this.certSha256,
    this.timeout = const Duration(seconds: 20),
  });

  final String host;
  final int? port;
  final FtpSecurity security;

  /// `null` logs in anonymously.
  final String? user;
  final String? password;

  /// SHA-256 of a self-signed certificate the user chose to trust.
  final String? certSha256;
  final Duration timeout;

  int get effectivePort =>
      port ?? (security == FtpSecurity.implicit ? 990 : 21);
}

/// One server reply: a three-digit code and its text lines.
final class FtpReply {
  const FtpReply(this.code, this.lines);

  final int code;
  final List<String> lines;

  String get summary => '$code ${lines.isEmpty ? '' : lines.first}'.trim();
}

const int _maxLine = 16 << 10;
const int _maxReplyLines = 4000;
const int _maxListing = 32 << 20;
const int _readAheadLimit = 8 << 20;

final RegExp _replyStart = RegExp(r'^(\d{3})([ -])(.*)$');
final RegExp _epsv = RegExp(r'\(([^\d])\1\1(\d{1,5})\1\)');
final RegExp _pasv = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)');

/// One logged-in control connection. Commands run one at a time.
final class FtpConnection {
  FtpConnection._(this.options, this._uri, this._socket) {
    _listen();
  }

  final FtpOptions options;
  final Uri _uri;
  Socket _socket;
  late StreamSubscription<Uint8List> _sub;
  final List<int> _pending = [];
  String? _multi;
  List<String> _lines = [];
  final List<FtpReply> _ready = [];
  final List<Completer<FtpReply>> _waiters = [];
  Object? _failure;
  bool _protected = false;
  bool _noEpsv = false;
  String? _rejectedFingerprint;
  Set<String> features = const {};
  Future<void> _tail = Future.value();

  bool get isOpen => _failure == null;

  /// Connects, upgrades to TLS as configured and logs in.
  static Future<FtpConnection> open(
    FtpOptions o,
    Uri uri,
    NetworkPolicy policy,
  ) async {
    if (!policy.isUserConfiguredHost(o.host)) {
      throw VirtualFileException(
        VirtualFileError.permissionDenied,
        uri,
        'host not configured',
      );
    }
    if (policy case final HostUseRecorder r) {
      r.recordHostUse(o.host, DateTime.now().toUtc());
    }
    String? rejected;
    bool onBad(X509Certificate cert) {
      final fp = certificateFingerprint(cert.der);
      if (fp == o.certSha256) return true;
      rejected = fp;
      return false;
    }

    final Socket socket;
    try {
      socket = o.security == FtpSecurity.implicit
          ? await SecureSocket.connect(
              o.host,
              o.effectivePort,
              onBadCertificate: onBad,
              timeout: o.timeout,
            )
          : await Socket.connect(o.host, o.effectivePort, timeout: o.timeout);
    } on HandshakeException catch (e) {
      throw _tlsError(uri, rejected, e);
    } on SocketException catch (e) {
      throw VirtualFileException(VirtualFileError.unreachable, uri, '$e');
    }
    final c = FtpConnection._(o, uri, socket)
      .._protected = o.security == FtpSecurity.implicit;
    try {
      await c._login();
      return c;
    } catch (_) {
      c.destroy();
      rethrow;
    }
  }

  void _listen() {
    _sub = _socket.listen(_onData, onError: _onError, onDone: _onDone);
  }

  Future<void> _login() async {
    final greeting = await _next();
    if (greeting.code != 220) throw _replyError(greeting, _uri);
    if (options.security == FtpSecurity.explicit) {
      final auth = await _send('AUTH TLS');
      if (auth.code != 234) {
        throw VirtualFileException(
          VirtualFileError.unsupported,
          _uri,
          'server refused AUTH TLS: ${auth.summary}',
        );
      }
      _sub.pause();
      try {
        _socket = await SecureSocket.secure(
          _socket,
          host: options.host,
          onBadCertificate: _onBadCertificate,
        ).timeout(options.timeout);
      } on HandshakeException catch (e) {
        throw _tlsError(_uri, _rejectedFingerprint, e);
      }
      _listen();
      _protected = true;
    }
    var r = await _send('USER ${options.user ?? 'anonymous'}');
    if (r.code == 331 || r.code == 332) {
      r = await _send('PASS ${options.password ?? 'anonymous@'}');
    }
    if (r.code != 230 && r.code != 202) {
      throw VirtualFileException(
        VirtualFileError.authenticationRequired,
        _uri,
        '${r.code}',
      );
    }
    if (_protected) {
      await _expect('PBSZ 0', const {200});
      await _expect('PROT P', const {200});
    }
    await _expect('TYPE I', const {200});
    final feat = await _send('FEAT');
    if (feat.code == 211) {
      features = {
        for (final l in feat.lines.skip(1))
          if (l.trim().isNotEmpty) l.trim().split(' ').first.toUpperCase(),
      };
    }
    if (features.contains('UTF8')) await _send('OPTS UTF8 ON');
  }

  bool _onBadCertificate(X509Certificate cert) {
    final fp = certificateFingerprint(cert.der);
    if (fp == options.certSha256) return true;
    _rejectedFingerprint = fp;
    return false;
  }

  /// Runs [op] after every earlier operation on this connection finished.
  Future<T> run<T>(Future<T> Function() op) {
    final f = _tail.then((_) => op());
    _tail = f.then<void>((_) {}, onError: (Object _) {});
    return f;
  }

  // ---- reply parsing ----

  void _onData(Uint8List data) {
    for (final b in data) {
      if (b == 10) {
        final line = utf8.decode(_pending, allowMalformed: true);
        _pending.clear();
        _line(line);
        if (_failure != null) return;
      } else if (b != 13) {
        if (_pending.length >= _maxLine) {
          return _fail(
            VirtualFileException(VirtualFileError.io, _uri, 'reply too long'),
          );
        }
        _pending.add(b);
      }
    }
  }

  void _line(String line) {
    final multi = _multi;
    if (multi == null) {
      final m = _replyStart.firstMatch(line);
      if (m == null) {
        return _fail(
          VirtualFileException(VirtualFileError.io, _uri, 'not an FTP reply'),
        );
      }
      if (m[2] == '-') {
        _multi = m[1];
        _lines = [m[3]!];
      } else {
        _emit(FtpReply(int.parse(m[1]!), [m[3]!]));
      }
    } else if (line.startsWith('$multi ')) {
      _lines.add(line.substring(4));
      _multi = null;
      _emit(FtpReply(int.parse(multi), _lines));
    } else {
      if (_lines.length >= _maxReplyLines) {
        return _fail(
          VirtualFileException(VirtualFileError.io, _uri, 'reply too long'),
        );
      }
      _lines.add(line);
    }
  }

  void _emit(FtpReply r) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(r);
    } else {
      _ready.add(r);
    }
  }

  void _onError(Object e) =>
      _fail(VirtualFileException(VirtualFileError.unreachable, _uri, '$e'));

  void _onDone() => _fail(
    VirtualFileException(VirtualFileError.closed, _uri, 'connection closed'),
  );

  void _fail(Object error) {
    _failure ??= error;
    for (final w in _waiters) {
      w.completeError(_failure!);
    }
    _waiters.clear();
    _socket.destroy();
  }

  Future<FtpReply> _next() {
    if (_ready.isNotEmpty) return Future.value(_ready.removeAt(0));
    if (_failure case final Object f) return Future.error(f);
    final c = Completer<FtpReply>();
    _waiters.add(c);
    return c.future.timeout(
      options.timeout,
      onTimeout: () {
        final e = VirtualFileException(
          VirtualFileError.timeout,
          _uri,
          'no reply within ${options.timeout.inSeconds} s',
        );
        _fail(e);
        throw e;
      },
    );
  }

  Future<FtpReply> _send(String command) {
    if (_failure case final Object f) return Future.error(f);
    if (command.contains('\r') || command.contains('\n')) {
      return Future.error(
        VirtualFileException(VirtualFileError.notFound, _uri, 'bad name'),
      );
    }
    _socket.write('$command\r\n');
    return _next();
  }

  Future<FtpReply> _expect(String command, Set<int> ok, [Uri? uri]) async {
    final r = await _send(command);
    if (!ok.contains(r.code)) throw _replyError(r, uri ?? _uri);
    return r;
  }

  // ---- commands (callers hold [run]) ----

  Future<FtpReply> command(String command) => _send(command);

  Future<FtpReply> expect(String command, Set<int> ok, Uri uri) =>
      _expect(command, ok, uri);

  Future<Socket> _passive(Uri uri) async {
    final address = _socket.remoteAddress;
    if (!_noEpsv) {
      final r = await _send('EPSV');
      if (r.code == 229) {
        final m = _epsv.firstMatch(r.lines.join(' '));
        if (m != null) {
          return await _connectData(address, int.parse(m[2]!), uri);
        }
      }
      _noEpsv = true;
    }
    final r = await _expect('PASV', const {227}, uri);
    final m = _pasv.firstMatch(r.lines.join(' '));
    if (m == null) {
      throw VirtualFileException(VirtualFileError.io, uri, r.summary);
    }
    // The address in the reply is ignored: data goes to the control host
    // only (no FXP bounce to another machine, works behind NAT).
    return await _connectData(
      address,
      int.parse(m[5]!) * 256 + int.parse(m[6]!),
      uri,
    );
  }

  Future<Socket> _connectData(InternetAddress a, int port, Uri uri) async {
    try {
      return await Socket.connect(a, port, timeout: options.timeout);
    } on SocketException catch (e) {
      throw VirtualFileException(VirtualFileError.unreachable, uri, '$e');
    }
  }

  /// Starts a transfer; returns the data socket once the server accepted it.
  Future<Socket> transfer(String command, Uri uri) async {
    final raw = await _passive(uri);
    final pre = _send(command);
    final tls = _protected
        ? SecureSocket.secure(
            raw,
            host: options.host,
            onBadCertificate: _onBadCertificate,
          )
        : null;
    final FtpReply r;
    try {
      r = await pre;
    } catch (_) {
      raw.destroy();
      _drop(tls);
      rethrow;
    }
    if (r.code != 125 && r.code != 150) {
      raw.destroy();
      _drop(tls);
      throw _replyError(r, uri);
    }
    if (tls == null) return raw;
    try {
      return await tls.timeout(options.timeout);
    } on HandshakeException catch (e) {
      raw.destroy();
      throw _tlsError(uri, _rejectedFingerprint, e);
    }
  }

  static void _drop(Future<SecureSocket>? tls) =>
      unawaited(tls?.then<void>((s) => s.destroy(), onError: (Object _) {}));

  /// The final reply of a transfer whose data stream ended.
  Future<void> finish(Uri uri) async {
    final r = await _next();
    if (r.code != 226 && r.code != 250) throw _replyError(r, uri);
  }

  /// Resynchronises after the client cut a transfer short: the server answers
  /// the transfer (426/451/226), then the NOOP. Anything else drops the link.
  Future<void> afterAbort() async {
    try {
      _socket.write('NOOP\r\n');
      for (var i = 0; i < 4; i++) {
        final r = await _next();
        if (r.code == 200) return;
      }
    } on Object catch (_) {
      // falls through to destroy
    }
    destroy();
  }

  Future<List<int>> readAll(String command, Uri uri) async {
    final data = await transfer(command, uri);
    final out = BytesBuilder(copy: false);
    try {
      await for (final chunk in data) {
        out.add(chunk);
        if (out.length > _maxListing) {
          data.destroy();
          destroy();
          throw VirtualFileException(VirtualFileError.io, uri, 'too large');
        }
      }
    } on SocketException catch (e) {
      destroy();
      throw VirtualFileException(VirtualFileError.io, uri, '$e');
    }
    await finish(uri);
    return out.takeBytes();
  }

  Future<void> quit() async {
    if (_failure != null) return;
    try {
      _socket.write('QUIT\r\n');
      await _next().timeout(const Duration(seconds: 2));
    } on Object catch (_) {
      // best effort
    }
    destroy();
  }

  void destroy() {
    _failure ??= VirtualFileException(VirtualFileError.closed, _uri);
    for (final w in _waiters) {
      w.completeError(_failure!);
    }
    _waiters.clear();
    unawaited(_sub.cancel());
    _socket.destroy();
  }
}

VirtualFileException _tlsError(Uri uri, String? fp, Object e) => fp == null
    ? VirtualFileException(VirtualFileError.io, uri, '$e')
    : VirtualFileException(VirtualFileError.untrustedCertificate, uri, fp);

VirtualFileException _replyError(FtpReply r, Uri uri) {
  final text = r.lines.join(' ').toLowerCase();
  final error = switch (r.code) {
    530 || 331 || 332 => VirtualFileError.authenticationRequired,
    452 || 552 => VirtualFileError.noSpace,
    553 => VirtualFileError.permissionDenied,
    421 => VirtualFileError.closed,
    500 || 501 || 502 || 504 || 522 => VirtualFileError.unsupported,
    550 || 450 || 451
        when text.contains('permission') ||
            text.contains('denied') ||
            text.contains('not allowed') =>
      VirtualFileError.permissionDenied,
    550 when text.contains('exists') && !text.contains('not') =>
      VirtualFileError.alreadyExists,
    550 || 450 => VirtualFileError.notFound,
    _ => VirtualFileError.io,
  };
  return VirtualFileException(error, uri, r.summary);
}

/// Facts of one MLSD/MLST line (`type=file;size=3;modify=2026…; name`).
(String, Map<String, String>)? parseMlsx(String line) {
  final sp = line.indexOf(' ');
  if (sp < 0) return null;
  final facts = <String, String>{};
  for (final f in line.substring(0, sp).split(';')) {
    final eq = f.indexOf('=');
    if (eq > 0) facts[f.substring(0, eq).toLowerCase()] = f.substring(eq + 1);
  }
  return (line.substring(sp + 1), facts);
}

/// `YYYYMMDDHHMMSS[.sss]` (UTC) from MDTM and MLSx `modify`.
DateTime? parseFtpTime(String? s) {
  if (s == null || s.length < 14) return null;
  final n = [
    for (final (a, b) in const [
      (0, 4),
      (4, 6),
      (6, 8),
      (8, 10),
      (10, 12),
      (12, 14),
    ])
      int.tryParse(s.substring(a, b)),
  ];
  if (n.contains(null)) return null;
  return DateTime.utc(n[0]!, n[1]!, n[2]!, n[3]!, n[4]!, n[5]!);
}

/// Browse, stream and manage files on an FTP/FTPS server.
final class FtpFileSystem implements MutableFileSystem {
  FtpFileSystem(this.options, this.policy);

  final FtpOptions options;
  final NetworkPolicy policy;
  FtpConnection? _control;

  @override
  Set<String> get schemes => const {'ftp', 'ftps', 'ftpes'};

  @override
  Set<VirtualFsCapability> get capabilities => const {
    VirtualFsCapability.list,
    VirtualFsCapability.write,
    VirtualFsCapability.rename,
    VirtualFsCapability.delete,
  };
  Future<FtpConnection>? _connecting;

  Future<FtpConnection> _connection(Uri uri) {
    if (_control case final c? when c.isOpen) return Future.value(c);
    return _connecting ??= FtpConnection.open(options, uri, policy).then(
      (c) {
        _connecting = null;
        return _control = c;
      },
      onError: (Object e, StackTrace st) {
        _connecting = null;
        return Future<FtpConnection>.error(e, st);
      },
    );
  }

  Future<T> _run<T>(Uri uri, Future<T> Function(FtpConnection c) op) async {
    final c = await _connection(uri);
    return await _guard(uri, () => c.run(() => op(c)));
  }

  static String path(Uri uri) {
    final p = Uri.decodeComponent(uri.path);
    if (p.contains('\r') || p.contains('\n') || p.contains('\x00')) {
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

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final entries = await _run(directory, (c) => _list(c, directory));
    yield* Stream.fromIterable(entries);
  }

  Future<List<VirtualEntry>> _list(FtpConnection c, Uri dir) async {
    final p = path(dir);
    // RFC 3659 §7: a server that offers MLST also implements MLSD.
    if (c.features.contains('MLST') || c.features.contains('MLSD')) {
      final text = utf8.decode(
        await c.readAll('MLSD $p', dir),
        allowMalformed: true,
      );
      return [
        for (final line in const LineSplitter().convert(text))
          if (parseMlsx(line.trim()) case (final name, final f)
              when f['type'] != 'cdir' &&
                  f['type'] != 'pdir' &&
                  name != '.' &&
                  name != '..')
            VirtualEntry(
              uri: _child(dir, name),
              name: name,
              isDirectory: f['type'] == 'dir',
              size: f['type'] == 'dir' ? null : int.tryParse(f['size'] ?? ''),
              modified: parseFtpTime(f['modify']),
            ),
      ];
    }
    await c.expect('CWD $p', const {250}, dir);
    final text = utf8.decode(
      await c.readAll('LIST', dir),
      allowMalformed: true,
    );
    return [
      for (final e in parseListing(text))
        if (e.name != '.' && e.name != '..')
          VirtualEntry(
            uri: _child(dir, e.name),
            name: e.name,
            isDirectory: e.isDirectory,
            size: e.isDirectory ? null : e.size,
            modified: e.modified,
          ),
    ];
  }

  @override
  Future<VirtualEntry> stat(Uri uri) => _run(uri, (c) => _stat(c, uri));

  Future<VirtualEntry> _stat(FtpConnection c, Uri uri) async {
    final p = path(uri);
    final segs = uri.pathSegments.where((s) => s.isNotEmpty);
    final name = segs.isEmpty ? '/' : segs.last;
    if (c.features.contains('MLST')) {
      final r = await c.command('MLST $p');
      if (r.code != 250) throw _replyError(r, uri);
      for (final l in r.lines.skip(1)) {
        if (parseMlsx(l.trim()) case (_, final f)) {
          final dir = f['type'] == 'dir' || f['type'] == 'cdir';
          return VirtualEntry(
            uri: uri,
            name: name,
            isDirectory: dir,
            size: dir ? null : int.tryParse(f['size'] ?? ''),
            modified: parseFtpTime(f['modify']),
          );
        }
      }
    }
    final size = await c.command('SIZE $p');
    if (size.code == 213) {
      final mdtm = await c.command('MDTM $p');
      return VirtualEntry(
        uri: uri,
        name: name,
        isDirectory: false,
        size: int.tryParse(size.lines.first.trim()),
        modified: mdtm.code == 213
            ? parseFtpTime(mdtm.lines.first.trim())
            : null,
      );
    }
    final cwd = await c.command('CWD $p');
    if (cwd.code == 250) {
      return VirtualEntry(uri: uri, name: name, isDirectory: true);
    }
    throw _replyError(size, uri);
  }

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
    return _FtpFile(this, uri, e.size);
  }

  @override
  Future<Uri> createDirectory(Uri parent, String name) async {
    final uri = _child(parent, _checkName(name, parent));
    return await _run(uri, (c) async {
      final p = path(uri);
      final r = await c.command('MKD $p');
      if (r.code == 257 || r.code == 250) return uri;
      // Servers answer an existing name with a generic 550.
      if ((await c.command('CWD $p')).code == 250 ||
          (await c.command('SIZE $p')).code == 213) {
        throw VirtualFileException(VirtualFileError.alreadyExists, uri);
      }
      throw _replyError(r, uri);
    });
  }

  @override
  Future<Uri> rename(Uri uri, String newName) async =>
      await _renameTo(uri, _child(_parent(uri), _checkName(newName, uri)));

  @override
  Future<Uri> move(Uri uri, Uri directory) async {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty);
    return await _renameTo(uri, _child(directory, segs.last));
  }

  Future<Uri> _renameTo(Uri from, Uri to) => _run(from, (c) async {
    final p = path(to);
    if ((await c.command('SIZE $p')).code == 213 ||
        (await c.command('CWD $p')).code == 250) {
      throw VirtualFileException(VirtualFileError.alreadyExists, to);
    }
    await c.expect('RNFR ${path(from)}', const {350}, from);
    await c.expect('RNTO $p', const {250}, to);
    return to;
  });

  @override
  Future<void> delete(Uri uri, {bool recursive = false}) =>
      _run(uri, (c) => _delete(c, uri, recursive: recursive));

  Future<void> _delete(
    FtpConnection c,
    Uri uri, {
    required bool recursive,
  }) async {
    final e = await _stat(c, uri);
    if (!e.isDirectory) {
      await c.expect('DELE ${path(uri)}', const {250}, uri);
      return;
    }
    if (recursive) {
      for (final child in await _list(c, uri)) {
        await _delete(c, child.uri, recursive: true);
      }
    }
    await c.expect('RMD ${path(uri)}', const {250}, uri);
  }

  @override
  Future<VirtualFileWriter> create(Uri uri) async {
    final c = await FtpConnection.open(options, uri, policy);
    try {
      final exists = await c.command('SIZE ${path(uri)}');
      if (exists.code == 213) {
        throw VirtualFileException(VirtualFileError.alreadyExists, uri);
      }
      final data = await _guard(
        uri,
        () => c.transfer('STOR ${path(uri)}', uri),
      );
      return _FtpWriter(c, data, uri);
    } catch (_) {
      c.destroy();
      rethrow;
    }
  }

  static String _checkName(String name, Uri uri) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\r') ||
        name.contains('\n')) {
      throw VirtualFileException(VirtualFileError.notFound, uri, 'bad name');
    }
    return name;
  }

  /// Closes the browsing connection.
  Future<void> close() async {
    final c = _control;
    _control = null;
    await c?.quit();
  }
}

Future<T> _guard<T>(Uri uri, Future<T> Function() op) async {
  try {
    return await op();
  } on VirtualFileException {
    rethrow;
  } on TimeoutException catch (e) {
    throw VirtualFileException(VirtualFileError.timeout, uri, '$e');
  } on SocketException catch (e) {
    throw VirtualFileException(VirtualFileError.unreachable, uri, '$e');
  } on TlsException catch (e) {
    throw VirtualFileException(VirtualFileError.io, uri, '$e');
  }
}

/// Random access over RETR with REST: sequential reads continue the open
/// transfer; a seek cuts it and restarts at the new offset.
final class _FtpFile implements VirtualFile {
  _FtpFile(this._fs, this.uri, this._length);

  final FtpFileSystem _fs;
  @override
  final Uri uri;
  final int? _length;

  @override
  bool get isSeekable => true;
  FtpConnection? _conn;
  _Retr? _retr;
  bool _closed = false;
  Future<void> _tail = Future.value();

  @override
  Future<int?> length() async => _length;

  @override
  Future<Uint8List> read(int offset, int length) {
    final f = _tail.then((_) => _read(offset, length));
    _tail = f.then<void>((_) {}, onError: (Object _) {});
    return f;
  }

  Future<Uint8List> _read(int offset, int length) async {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    final size = _length;
    if (length <= 0 || (size != null && offset >= size)) return Uint8List(0);
    return await _guard(uri, () async {
      var retr = _retr;
      if (retr == null || retr.position != offset || retr.failed) {
        await _stop();
        var c = _conn;
        if (c == null || !c.isOpen) {
          c = _conn = await FtpConnection.open(_fs.options, uri, _fs.policy);
        }
        if (offset > 0) {
          await c.expect('REST $offset', const {350}, uri);
        }
        final data = await c.transfer('RETR ${FtpFileSystem.path(uri)}', uri);
        retr = _retr = _Retr(c, data, offset, uri);
      }
      return await retr.take(length);
    });
  }

  Future<void> _stop() async {
    final r = _retr;
    _retr = null;
    if (r == null) return;
    await r.stop();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _tail;
    await _stop();
    await _conn?.quit();
    _conn = null;
  }
}

final class _Retr {
  _Retr(this._conn, this._data, this.position, this._uri) {
    _sub = _data.listen(
      (chunk) {
        _chunks.add(chunk);
        _buffered += chunk.length;
        if (_buffered > _readAheadLimit) _sub.pause();
        _signal();
      },
      onError: (Object e) {
        _error = VirtualFileException(VirtualFileError.io, _uri, '$e');
        _signal();
      },
      onDone: () {
        _done = true;
        _finished = _conn.finish(_uri);
        _signal();
      },
    );
  }

  final FtpConnection _conn;
  final Socket _data;
  final Uri _uri;
  late final StreamSubscription<Uint8List> _sub;
  final List<Uint8List> _chunks = [];
  int _buffered = 0;
  int position;
  bool _done = false;
  VirtualFileException? _error;
  Future<void>? _finished;
  Completer<void>? _wake;

  bool get failed => _error != null;

  void _signal() {
    final w = _wake;
    _wake = null;
    w?.complete();
  }

  Future<Uint8List> take(int n) async {
    while (_buffered < n && !_done && _error == null) {
      if (_sub.isPaused) _sub.resume();
      final w = _wake = Completer<void>();
      await w.future.timeout(_conn.options.timeout);
    }
    if (_error case final e? when _buffered == 0) throw e;
    final want = n < _buffered ? n : _buffered;
    final out = Uint8List(want);
    var at = 0;
    while (at < want) {
      final c = _chunks.first;
      final k = want - at < c.length ? want - at : c.length;
      out.setRange(at, at + k, c);
      at += k;
      if (k == c.length) {
        _chunks.removeAt(0);
      } else {
        _chunks[0] = Uint8List.sublistView(c, k);
      }
    }
    _buffered -= want;
    position += want;
    if (_buffered < _readAheadLimit ~/ 2 && _sub.isPaused) _sub.resume();
    return out;
  }

  Future<void> stop() async {
    if (_done) {
      try {
        await _finished;
      } on Object catch (_) {
        _conn.destroy();
      }
      return;
    }
    await _sub.cancel();
    _data.destroy();
    await _conn.run(_conn.afterAbort);
  }
}

final class _FtpWriter implements VirtualFileWriter {
  _FtpWriter(this._conn, this._data, this.uri);

  final FtpConnection _conn;
  final Socket _data;
  @override
  final Uri uri;
  var _ended = false;

  @override
  Future<void> write(List<int> bytes) => _guard(uri, () async {
    if (_ended) throw VirtualFileException(VirtualFileError.closed, uri);
    _data.add(bytes);
    await _data.flush();
  });

  @override
  Future<void> close() => _guard(uri, () async {
    if (_ended) return;
    _ended = true;
    try {
      await _data.close();
      await _conn.finish(uri);
    } finally {
      await _conn.quit();
    }
  });

  @override
  Future<void> abort() async {
    if (_ended) return;
    _ended = true;
    _data.destroy();
    try {
      await _conn.afterAbort();
      if (_conn.isOpen) {
        await _conn.command('DELE ${FtpFileSystem.path(uri)}');
      }
    } on Object catch (_) {
      // best effort: the partial upload stays if the server refuses
    }
    await _conn.quit();
  }
}
