import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A small FTP/FTPS server over a directory for the NET-004 tests: enough
/// of RFC 959/2389/2428/3659/4217 to exercise the client, with switches for
/// the features real servers lack (MLSD, EPSV).
final class TestFtpServer {
  TestFtpServer._(this.root, this._server, this.options);

  final Directory root;
  final Object _server;
  final TestFtpOptions options;
  final List<String> commands = [];
  int sessions = 0;

  int get port => switch (_server) {
    final ServerSocket s => s.port,
    final SecureServerSocket s => s.port,
    _ => throw StateError('server'),
  };

  static Future<TestFtpServer> start(
    Directory root, {
    TestFtpOptions options = const TestFtpOptions(),
  }) async {
    final Object server;
    if (options.implicitTls) {
      final s = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        options.context,
      );
      server = s;
      final t = TestFtpServer._(root, s, options);
      // A client rejecting the certificate surfaces here; it is expected.
      s.listen(t._session, onError: (Object _) {});
      return t;
    }
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server = s;
    final t = TestFtpServer._(root, server, options);
    s.listen(t._session);
    return t;
  }

  Future<void> close() async {
    switch (_server) {
      case final ServerSocket s:
        await s.close();
      case final SecureServerSocket s:
        await s.close();
    }
  }

  void _session(Socket socket) {
    sessions++;
    _Session(this, socket).start();
  }
}

final class TestFtpOptions {
  const TestFtpOptions({
    this.user = 'test',
    this.password = 'testpass',
    this.mlsd = true,
    this.epsv = true,
    this.context,
    this.implicitTls = false,
    this.requireTls = false,
  });

  final String user;
  final String password;
  final bool mlsd;
  final bool epsv;

  /// Certificate and key for AUTH TLS / implicit TLS; `null` disables TLS.
  final SecurityContext? context;
  final bool implicitTls;
  final bool requireTls;
}

final class _Session {
  _Session(this.server, this.socket) : _protected = server.options.implicitTls;

  final TestFtpServer server;
  Socket socket;
  late StreamSubscription<Uint8List> _sub;
  final List<int> _pending = [];
  final _lines = StreamController<String>();
  bool _loggedIn = false;
  bool _tls = false;
  bool _protected;
  String? _user;
  String _cwd = '/';
  int _rest = 0;
  String? _renameFrom;
  ServerSocket? _passive;

  TestFtpOptions get o => server.options;

  void start() {
    _tls = o.implicitTls;
    _listen();
    _reply(220, 'mediahro test ftp');
    unawaited(_loop());
  }

  void _listen() {
    _sub = socket.listen(
      (data) {
        for (final b in data) {
          if (b == 10) {
            _lines.add(utf8.decode(_pending, allowMalformed: true));
            _pending.clear();
          } else if (b != 13) {
            _pending.add(b);
          }
        }
      },
      onDone: () => unawaited(_lines.close()),
      onError: (Object _) => unawaited(_lines.close()),
    );
  }

  void _reply(int code, String text) => socket.write('$code $text\r\n');

  Future<void> _loop() async {
    await for (final line in _lines.stream) {
      server.commands.add(line.startsWith('PASS ') ? 'PASS ***' : line);
      final sp = line.indexOf(' ');
      final cmd = (sp < 0 ? line : line.substring(0, sp)).toUpperCase();
      final arg = sp < 0 ? '' : line.substring(sp + 1);
      try {
        if (!await _handle(cmd, arg)) break;
      } on Object catch (e) {
        _reply(451, 'error $e');
      }
    }
    await _passive?.close();
    socket.destroy();
  }

  String _abs(String arg) {
    if (arg.isEmpty) return _cwd;
    final joined = arg.startsWith('/')
        ? arg
        : '${_cwd == '/' ? '' : _cwd}/$arg';
    final out = <String>[];
    for (final s in joined.split('/')) {
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else {
        out.add(s);
      }
    }
    return '/${out.join('/')}';
  }

  String _local(String abs) =>
      '${server.root.path}${abs.replaceAll('/', Platform.pathSeparator)}';

  Future<bool> _handle(String cmd, String arg) async {
    if (!_loggedIn &&
        !const {
          'USER',
          'PASS',
          'AUTH',
          'QUIT',
          'FEAT',
          'PBSZ',
          'PROT',
        }.contains(cmd)) {
      _reply(530, 'Please login with USER and PASS.');
      return true;
    }
    switch (cmd) {
      case 'AUTH':
        if (o.context == null || arg.toUpperCase() != 'TLS') {
          _reply(502, 'not supported');
          return true;
        }
        _reply(234, 'Proceed with negotiation.');
        await socket.flush();
        _sub.pause();
        try {
          socket = await SecureSocket.secureServer(socket, o.context);
        } on Object {
          // The client refused the certificate and hung up.
          return false;
        }
        _tls = true;
        _listen();
      case 'USER':
        if (o.requireTls && !_tls) {
          _reply(530, 'Non-anonymous sessions must use encryption.');
          return true;
        }
        _user = arg;
        _reply(331, 'Please specify the password.');
      case 'PASS':
        if (_user == o.user && arg == o.password) {
          _loggedIn = true;
          _reply(230, 'Login successful.');
        } else {
          _reply(530, 'Login incorrect.');
        }
      case 'PBSZ':
        _reply(200, 'PBSZ=0');
      case 'PROT':
        _protected = arg.toUpperCase() == 'P';
        _reply(200, 'PROT now ${_protected ? 'Private' : 'Clear'}.');
      case 'TYPE':
        _reply(200, 'Switching to Binary mode.');
      case 'FEAT':
        socket.write('211-Features:\r\n');
        for (final f in [
          if (o.epsv) 'EPSV',
          if (o.mlsd) 'MLST type*;size*;modify*;',
          'MDTM',
          'REST STREAM',
          'SIZE',
          'UTF8',
          if (o.context != null) 'AUTH TLS',
        ]) {
          socket.write(' $f\r\n');
        }
        _reply(211, 'End');
      case 'OPTS':
        _reply(200, 'Always in UTF8 mode.');
      case 'NOOP':
        _reply(200, 'NOOP ok.');
      case 'PWD':
        _reply(257, '"$_cwd" is the current directory');
      case 'CWD':
        final p = _abs(arg);
        if (Directory(_local(p)).existsSync()) {
          _cwd = p;
          _reply(250, 'Directory successfully changed.');
        } else {
          _reply(550, 'Failed to change directory.');
        }
      case 'EPSV':
        if (!o.epsv) {
          _reply(500, 'Unknown command.');
          return true;
        }
        await _openPassive();
        _reply(229, 'Entering Extended Passive Mode (|||${_passive!.port}|)');
      case 'PASV':
        await _openPassive();
        final pt = _passive!.port;
        // Deliberately advertise a foreign address: the client must ignore it.
        _reply(227, 'Entering Passive Mode (10,9,8,7,${pt >> 8},${pt & 255}).');
      case 'SIZE':
        final f = File(_local(_abs(arg)));
        if (f.existsSync()) {
          _reply(213, '${f.lengthSync()}');
        } else {
          _reply(550, 'Could not get file size.');
        }
      case 'MDTM':
        final f = File(_local(_abs(arg)));
        if (f.existsSync()) {
          _reply(213, _time(f.lastModifiedSync()));
        } else {
          _reply(550, 'Could not get file modification time.');
        }
      case 'MLST':
        if (!o.mlsd) {
          _reply(500, 'Unknown command.');
          return true;
        }
        final p = _abs(arg);
        final fact = _facts(p);
        if (fact == null) {
          _reply(550, 'No such file.');
        } else {
          socket.write('250-Listing $p\r\n $fact $p\r\n');
          _reply(250, 'End');
        }
      case 'MLSD':
        if (!o.mlsd) {
          _reply(500, 'Unknown command.');
          return true;
        }
        final p = _abs(arg);
        final dir = Directory(_local(p));
        if (!dir.existsSync()) {
          _reply(550, 'No such directory.');
          return true;
        }
        await _send(
          utf8.encode(
            [
              'type=cdir;modify=${_time(dir.statSync().modified)}; .',
              for (final e
                  in dir.listSync()..sort((a, b) => a.path.compareTo(b.path)))
                '${_facts('${p == '/' ? '' : p}/${_base(e.path)}')} ${_base(e.path)}',
            ].map((l) => '$l\r\n').join(),
          ),
        );
      case 'LIST':
        final p = _abs(arg.startsWith('-') ? '' : arg);
        final dir = Directory(_local(p));
        if (!dir.existsSync()) {
          _reply(550, 'No such directory.');
          return true;
        }
        await _send(
          utf8.encode(
            [
              for (final e
                  in dir.listSync()..sort((a, b) => a.path.compareTo(b.path)))
                _unixLine(e),
            ].map((l) => '$l\r\n').join(),
          ),
        );
      case 'REST':
        _rest = int.parse(arg);
        _reply(350, 'Restart position accepted ($_rest).');
      case 'RETR':
        final f = File(_local(_abs(arg)));
        if (!f.existsSync()) {
          _rest = 0;
          _reply(550, 'Failed to open file.');
          return true;
        }
        final from = _rest;
        _rest = 0;
        await _send(null, file: f, offset: from);
      case 'STOR':
        await _receive(File(_local(_abs(arg))));
      case 'MKD':
        final d = Directory(_local(_abs(arg)));
        if (d.existsSync()) {
          _reply(550, 'Create directory operation failed.');
        } else {
          d.createSync();
          _reply(257, '"${_abs(arg)}" created');
        }
      case 'RMD':
        final d = Directory(_local(_abs(arg)));
        try {
          d.deleteSync();
          _reply(250, 'Remove directory operation successful.');
        } on FileSystemException {
          _reply(550, 'Remove directory operation failed.');
        }
      case 'DELE':
        final f = File(_local(_abs(arg)));
        if (f.existsSync()) {
          f.deleteSync();
          _reply(250, 'Delete operation successful.');
        } else {
          _reply(550, 'Delete operation failed.');
        }
      case 'RNFR':
        final p = _abs(arg);
        if (FileSystemEntity.typeSync(_local(p)) ==
            FileSystemEntityType.notFound) {
          _reply(550, 'RNFR command failed.');
        } else {
          _renameFrom = p;
          _reply(350, 'Ready for RNTO.');
        }
      case 'RNTO':
        final from = _renameFrom;
        _renameFrom = null;
        if (from == null) {
          _reply(503, 'RNFR required first.');
          return true;
        }
        final src = _local(from);
        final dst = _local(_abs(arg));
        if (FileSystemEntity.isDirectorySync(src)) {
          Directory(src).renameSync(dst);
        } else {
          File(src).renameSync(dst);
        }
        _reply(250, 'Rename successful.');
      case 'QUIT':
        _reply(221, 'Goodbye.');
        await socket.flush();
        return false;
      default:
        _reply(502, 'Command not implemented.');
    }
    return true;
  }

  Future<void> _openPassive() async {
    await _passive?.close();
    _passive = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  }

  Future<Socket?> _accept() async {
    final p = _passive;
    _passive = null;
    if (p == null) {
      _reply(425, 'Use PORT or PASV first.');
      return null;
    }
    final raw = await p.first.timeout(const Duration(seconds: 10));
    await p.close();
    _reply(150, 'Here comes the data.');
    await socket.flush();
    if (!_protected) return raw;
    return await SecureSocket.secureServer(raw, o.context);
  }

  Future<void> _send(List<int>? bytes, {File? file, int offset = 0}) async {
    final data = await _accept();
    if (data == null) return;
    try {
      if (bytes != null) {
        data.add(bytes);
      } else {
        await data.addStream(file!.openRead(offset));
      }
      await data.close();
      _reply(226, 'Transfer complete.');
    } on Object {
      data.destroy();
      _reply(426, 'Failure writing network stream.');
    }
  }

  Future<void> _receive(File f) async {
    final data = await _accept();
    if (data == null) return;
    final sink = f.openWrite();
    try {
      await sink.addStream(data);
      await sink.close();
      _reply(226, 'Transfer complete.');
    } on Object {
      await sink.close();
      _reply(426, 'Failure reading network stream.');
    }
  }

  String? _facts(String abs) {
    final local = _local(abs);
    final type = FileSystemEntity.typeSync(local);
    if (type == FileSystemEntityType.notFound) return null;
    final st = File(local).statSync();
    return type == FileSystemEntityType.directory
        ? 'type=dir;modify=${_time(st.modified)};'
        : 'type=file;size=${st.size};modify=${_time(st.modified)};';
  }

  static String _base(String p) => p.split(RegExp(r'[\\/]')).last;

  static String _time(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _unixLine(FileSystemEntity e) {
    final st = e.statSync();
    final dir = st.type == FileSystemEntityType.directory;
    final m = st.modified.toUtc();
    return '${dir ? 'd' : '-'}rw-r--r--    1 1000     1000     ${dir ? 4096 : st.size} '
        '${_months[m.month - 1]} ${m.day.toString().padLeft(2)} ${m.year} ${_base(e.path)}';
  }
}

/// A throwaway self-signed certificate for `localhost` (generated per run,
/// never committed). `null` when openssl is not installed.
Future<SecurityContext?> testTlsContext(Directory dir) async {
  final key = '${dir.path}/key.pem';
  final cert = '${dir.path}/cert.pem';
  try {
    final r = await Process.run('openssl', [
      'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-days', '2', //
      '-subj', '/CN=localhost', '-keyout', key, '-out', cert,
    ]);
    if (r.exitCode != 0) return null;
  } on ProcessException {
    return null;
  }
  return SecurityContext()
    ..useCertificateChain(cert)
    ..usePrivateKey(key);
}
