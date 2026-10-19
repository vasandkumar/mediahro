import 'dart:typed_data';

import 'package:mediahro/platform/platform_facades.dart';

/// An SSH server as the platform facade would present it.
final class FakeSftp implements SftpFacade {
  FakeSftp({this.hostKey = 'SHA256:aaaa', this.password = 'pw'});

  String hostKey;
  final String password;
  final Map<String, Uint8List?> tree = {'/': null}; // null = directory
  final List<SftpEndpoint> connects = [];
  final Map<String, String> secrets = {};
  int open = 0;

  void file(String p, List<int> bytes) {
    tree[p] = Uint8List.fromList(bytes);
    var d = p.substring(0, p.lastIndexOf('/'));
    while (d.isNotEmpty) {
      tree[d] = null;
      d = d.substring(0, d.lastIndexOf('/'));
    }
  }

  @override
  Future<SftpSession> connect(SftpEndpoint e) async {
    connects.add(e);
    if (secrets[e.passwordSecretRef] != password) {
      throw Exception('auth failed');
    }
    open++;
    return _Session(this);
  }
}

final class _Session implements SftpSession {
  _Session(this.f);

  final FakeSftp f;

  @override
  String get hostKeySha256 => f.hostKey;

  SftpEntry _e(String p) {
    if (!f.tree.containsKey(p)) throw Exception('no such file: $p');
    final b = f.tree[p];
    return SftpEntry(
      path: p,
      isDirectory: b == null,
      size: b?.length,
      modified: DateTime.utc(2026),
    );
  }

  @override
  Future<List<SftpEntry>> list(String path) async {
    if (f.tree[path] != null || !f.tree.containsKey(path)) {
      throw Exception('not a directory');
    }
    final prefix = path == '/' ? '/' : '$path/';
    return [
      for (final p in f.tree.keys)
        if (p != path &&
            p.startsWith(prefix) &&
            !p.substring(prefix.length).contains('/'))
          _e(p),
    ];
  }

  @override
  Future<SftpEntry> stat(String path) async => _e(path);

  @override
  Future<Uint8List> read(String path, int offset, int length) async {
    final b = f.tree[path]!;
    final end = offset + length > b.length ? b.length : offset + length;
    return Uint8List.sublistView(b, offset, end);
  }

  @override
  Future<void> rename(String from, String to) async {
    for (final k in f.tree.keys.toList()) {
      if (k == from || k.startsWith('$from/')) {
        f.tree['$to${k.substring(from.length)}'] = f.tree.remove(k);
      }
    }
  }

  @override
  Future<void> delete(String path) async {
    if (f.tree.keys.any((k) => k.startsWith('$path/'))) {
      throw Exception('directory not empty');
    }
    f.tree.remove(path);
  }

  @override
  Future<void> mkdir(String path) async {
    if (f.tree.containsKey(path)) throw Exception('exists');
    f.tree[path] = null;
  }

  @override
  Future<SftpWriteSink> openWrite(String path, {bool truncate = true}) async =>
      _Sink(f, path);

  @override
  Future<void> close() async => f.open--;
}

final class _Sink implements SftpWriteSink {
  _Sink(this.f, this.path) {
    f.tree[path] = Uint8List(0);
  }

  final FakeSftp f;
  final String path;
  final BytesBuilder _b = BytesBuilder();

  @override
  Future<void> write(Uint8List data) async => _b.add(data);

  @override
  Future<void> close() async => f.tree[path] = _b.takeBytes();

  @override
  Future<void> abort() async => f.tree.remove(path);
}
