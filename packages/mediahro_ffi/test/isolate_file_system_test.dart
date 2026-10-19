import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

/// Blocking in-memory file system standing in for libsmb2/libnfs.
final class _MemSync implements SyncFileSystem {
  _MemSync(Map<String, List<int>> files) {
    files.forEach((k, v) {
      this.files[k] = Uint8List.fromList(v);
      final parts = k.split('/');
      for (var i = 1; i < parts.length; i++) {
        dirs.add(parts.sublist(0, i).join('/'));
      }
    });
  }

  final files = <String, Uint8List>{};
  final dirs = <String>{''};
  final open_ = <int, (String, BytesBuilder?)>{};
  int next = 1;

  Uri _u(String p) => Uri(scheme: 'smb', host: 'nas', path: '/share/$p');

  VirtualFileException _nf(String p) =>
      VirtualFileException(VirtualFileError.notFound, _u(p));

  @override
  List<VirtualEntry> list(String path) {
    if (!dirs.contains(path)) throw _nf(path);
    final prefix = path.isEmpty ? '' : '$path/';
    return [
      for (final d in dirs)
        if (d.startsWith(prefix) &&
            d != path &&
            !d.substring(prefix.length).contains('/'))
          VirtualEntry(
            uri: _u('$d/'),
            name: d.split('/').last,
            isDirectory: true,
          ),
      for (final f in files.keys)
        if (f.startsWith(prefix) && !f.substring(prefix.length).contains('/'))
          VirtualEntry(
            uri: _u(f),
            name: f.split('/').last,
            isDirectory: false,
            size: files[f]!.length,
          ),
    ];
  }

  @override
  VirtualEntry stat(String path) {
    if (dirs.contains(path)) {
      return VirtualEntry(
        uri: _u(path),
        name: path.split('/').last,
        isDirectory: true,
      );
    }
    final f = files[path] ?? (throw _nf(path));
    return VirtualEntry(
      uri: _u(path),
      name: path.split('/').last,
      isDirectory: false,
      size: f.length,
    );
  }

  @override
  int open(String path, {bool write = false, bool create = false}) {
    if (!write && !files.containsKey(path)) throw _nf(path);
    if (write) files[path] = Uint8List(0);
    open_[next] = (path, write ? BytesBuilder() : null);
    return next++;
  }

  @override
  int? length(int handle) => files[open_[handle]!.$1]?.length;

  @override
  Uint8List read(int handle, int offset, int length) {
    final f = files[open_[handle]!.$1]!;
    if (offset >= f.length) return Uint8List(0);
    return Uint8List.sublistView(
      f,
      offset,
      (offset + length).clamp(0, f.length),
    );
  }

  @override
  void write(int handle, int offset, List<int> bytes) =>
      open_[handle]!.$2!.add(bytes);

  @override
  void close(int handle) {
    final (p, b) = open_.remove(handle)!;
    if (b != null) files[p] = b.takeBytes();
  }

  @override
  void mkdir(String path) {
    if (!dirs.add(path)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, _u(path));
    }
  }

  @override
  void rename(String from, String to) {
    if (files.containsKey(to)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, _u(to));
    }
    files[to] = files.remove(from) ?? (throw _nf(from));
  }

  @override
  void unlink(String path) {
    if (files.remove(path) == null) throw _nf(path);
  }

  @override
  void rmdir(String path) {
    if (!dirs.remove(path)) throw _nf(path);
  }

  @override
  void dispose() {}
}

void main() {
  final root = Uri.parse('smb://nas/share/');
  late IsolateFileSystem fs;

  setUp(() {
    fs = IsolateFileSystem(
      root: root,
      schemes: const {'smb'},
      factory: () => _MemSync({
        'Films/a.mkv': List.generate(1000, (i) => i % 256),
        'readme.txt': [104, 105],
      }),
    );
  });
  tearDown(() => fs.close());

  test('NET-001 worker isolate serves list, stat and seekable reads', () async {
    final top = await fs.list(root).toList();
    expect(top.map((e) => (e.name, e.isDirectory)).toSet(), {
      ('Films', true),
      ('readme.txt', false),
    });
    final f = await fs.open(root.resolve('Films/a.mkv'));
    expect(await f.length(), 1000);
    expect(await f.read(998, 10), [998 % 256, 999 % 256]);
    final reads = await Future.wait([
      for (var i = 0; i < 20; i++) f.read(i * 10, 1),
    ]);
    expect(
      [for (final r in reads) r.single],
      [for (var i = 0; i < 20; i++) (i * 10) % 256],
    );
    await f.close();
    expect(() => f.read(0, 1), throwsA(isA<VirtualFileException>()));
    expect((await fs.stat(root.resolve('readme.txt'))).size, 2);
  });

  test('NET-001 errors cross the isolate boundary typed', () async {
    await expectLater(
      fs.open(root.resolve('nope.mkv')),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.notFound,
        ),
      ),
    );
    expect(
      () => fs.pathOf(Uri.parse('smb://other/share/x')),
      throwsA(isA<VirtualFileException>()),
    );
  });

  test(
    'FILE-002 on network shares: mkdir, atomic upload, rename, move, delete',
    () async {
      final dir = await fs.createDirectory(root, 'New');
      expect(dir.toString(), 'smb://nas/share/New/');
      final w = await fs.create(root.resolve('New/up.bin'));
      await w.write([1, 2]);
      await w.write([3]);
      expect((await fs.list(dir).toList()).map((e) => e.name), [
        '.up.bin.part',
      ], reason: 'hidden until closed');
      await w.close();
      expect((await fs.list(dir).toList()).map((e) => e.name), ['up.bin']);
      final renamed = await fs.rename(root.resolve('New/up.bin'), 'done.bin');
      final moved = await fs.move(renamed, root);
      final back = await fs.open(moved);
      expect(await back.read(0, 10), [1, 2, 3]);
      await back.close();
      await fs.delete(dir, recursive: true);
      await expectLater(fs.stat(dir), throwsA(isA<VirtualFileException>()));
    },
  );

  test('NET-001 SMB URIs carry share, domain and user', () {
    final o = smbOptionsFromUri(
      Uri.parse('smb://WORK;alice@nas.local:4455/Media/Films'),
    );
    expect(
      (o.server, o.share, o.domain, o.user, o.port),
      ('nas.local', 'Media', 'WORK', 'alice', 4455),
    );
    expect(
      () => smbOptionsFromUri(Uri.parse('smb://nas/')),
      throwsArgumentError,
    );
  });
}
