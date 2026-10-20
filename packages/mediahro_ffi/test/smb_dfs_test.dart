import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_ffi/src/smb2/smb2_dfs.dart';
import 'package:test/test.dart';

void main() {
  test(
    'NET-001 DFS referral request is REQ_GET_DFS_REFERRAL (level 4, UTF-16)',
    () {
      expect(encodeDfsReferralRequest(r'\h\s\l'), [
        4, 0, // MaxReferralLevel
        0x5c, 0, 0x68, 0, 0x5c, 0, 0x73, 0, 0x5c, 0, 0x6c, 0, // \h\s\l
        0, 0, // terminator
      ]);
    },
  );

  test('NET-001 DFS referral V3, V2 and V1 entries are parsed', () {
    final v3 = parseDfsReferral(
      referral([(3, r'\nas\dfs\linked', r'\nas\public')], consumed: 30),
    );
    expect(v3.pathConsumed, 30);
    expect(v3.targets.single.dfsPath, r'\nas\dfs\linked');
    expect(v3.targets.single.networkAddress, r'\nas\public');

    final v2 = parseDfsReferral(
      referral([(2, r'\nas\dfs\a', r'\other\media\sub')]),
    );
    expect(v2.targets.single.networkAddress, r'\other\media\sub');

    final v1 = parseDfsReferral(referral([(1, '', r'\nas\public')]));
    expect(v1.targets.single.networkAddress, r'\nas\public');
  });

  test('NET-001 malformed DFS referrals are refused, not over-read', () {
    final good = referral([(3, r'\nas\dfs\linked', r'\nas\public')]);
    // Cut inside the strings: the terminator is missing.
    expect(
      () => parseDfsReferral(Uint8List.sublistView(good, 0, good.length - 4)),
      throwsFormatException,
    );
    // Entry size past the end.
    expect(
      () => parseDfsReferral(Uint8List.sublistView(good, 0, 20)),
      throwsFormatException,
    );
    final many = Uint8List.fromList(good)..[2] = 200;
    expect(() => parseDfsReferral(many), throwsFormatException);
    expect(() => parseDfsReferral(Uint8List(4)), throwsFormatException);
  });

  group('NET-001 SmbDfsFileSystem', () {
    late _FakeRoot root;
    late _FakeShare target;
    late List<SmbOptions> connected;
    late SmbDfsFileSystem fs;

    setUp(() {
      root = _FakeRoot(
        const SmbOptions(server: 'nas', share: 'dfs', port: 1445, guest: true),
      )..dirs.add('');
      target = _FakeShare()
        ..dirs.addAll(['', 'Films'])
        ..files['Films/a.mkv'] = Uint8List.fromList([1, 2, 3]);
      connected = [];
      fs = SmbDfsFileSystem(
        root,
        connect: (o, hops) {
          connected.add(o);
          return target;
        },
      );
    });

    test('a link is resolved once and its subtree served by the target', () {
      final listed = fs.list('linked');
      expect(listed.map((e) => e.name), ['Films']);
      expect(
        listed.single.uri,
        Uri.parse('smb://nas/dfs/linked/Films/'),
        reason: 'entries keep the DFS namespace',
      );
      final o = connected.single;
      expect(
        (o.server, o.share, o.port, o.guest),
        ('nas', 'public', 1445, true),
      );

      final st = fs.stat('Linked/Films/a.mkv');
      expect(st.name, 'a.mkv');
      expect(st.uri, Uri.parse('smb://nas/dfs/Linked/Films/a.mkv'));
      expect(fs.stat('linked').name, 'linked');

      final h = fs.open('linked/Films/a.mkv');
      expect(fs.read(h, 1, 10), [2, 3]);
      fs.close(h);
      expect(root.referrals, 1, reason: 'the link is cached');
    });

    test('paths outside links stay on the root; other errors are kept', () {
      expect(fs.list(''), isEmpty);
      expect(
        () => fs.stat('missing'),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.notFound,
          ),
        ),
      );
      expect(root.referrals, 0);
    });

    test('rename across a link boundary is unsupported', () {
      fs.list('linked');
      expect(
        () => fs.rename('linked/Films/a.mkv', 'here.mkv'),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.unsupported,
          ),
        ),
      );
      fs.rename('linked/Films/a.mkv', 'linked/Films/b.mkv');
      expect(target.files.keys, contains('Films/b.mkv'));
    });

    test(r'a referral refused on the share is asked of IPC$', () {
      root.refuse = true;
      final ipc = _FakeRoot(root.options);
      final viaIpc = SmbDfsFileSystem(
        root,
        connect: (o, hops) => target,
        connectIpc: (o) {
          expect(o.share, r'IPC$');
          return ipc;
        },
      );
      expect(viaIpc.list('linked').map((e) => e.name), ['Films']);
      expect((root.referrals, ipc.referrals, ipc.disposed), (1, 1, true));
    });

    test('a referral the server refuses rethrows the original error', () {
      root.refuse = true;
      fs = SmbDfsFileSystem(
        root,
        connect: (o, hops) {
          connected.add(o);
          return target;
        },
        connectIpc: (o) => _FakeRoot(o)..refuse = true,
      );
      expect(
        () => fs.list('linked'),
        throwsA(
          isA<VirtualFileException>().having(
            (e) => e.error,
            'error',
            VirtualFileError.io,
          ),
        ),
      );
      expect(connected, isEmpty);
    });

    test('dispose releases the target share too', () {
      fs
        ..list('linked')
        ..dispose();
      expect(target.disposed, isTrue);
      expect(root.disposed, isTrue);
    });
  });
}

/// RESP_GET_DFS_REFERRAL with one entry per (version, dfsPath, address).
Uint8List referral(List<(int, String, String)> entries, {int consumed = 0}) {
  const sizes = {1: 8, 2: 22, 3: 34, 4: 34};
  final fixed = entries.fold(0, (n, e) => n + sizes[e.$1]!);
  final strings = BytesBuilder();
  final out = BytesBuilder()
    ..add(_u16(consumed))
    ..add(_u16(entries.length))
    ..add(_u32(0));
  var at = 8;
  final stringsAt = 8 + fixed;
  for (final (v, dfs, addr) in entries) {
    final size = v == 1 ? 8 + _utf16z(addr).length : sizes[v]!;
    if (v == 1) {
      out
        ..add(_u16(1))
        ..add(_u16(size))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_utf16z(addr));
      at += size;
      continue;
    }
    final dfsOff = stringsAt + strings.length - at;
    strings.add(_utf16z(dfs));
    final addrOff = stringsAt + strings.length - at;
    strings.add(_utf16z(addr));
    out
      ..add(_u16(v))
      ..add(_u16(size))
      ..add(_u16(1)) // ServerType: root
      ..add(_u16(0)); // ReferralEntryFlags
    if (v == 2) {
      out
        ..add(_u32(0)) // Proximity
        ..add(_u32(300)) // TimeToLive
        ..add(_u16(dfsOff))
        ..add(_u16(dfsOff))
        ..add(_u16(addrOff));
    } else {
      out
        ..add(_u32(300))
        ..add(_u16(dfsOff))
        ..add(_u16(dfsOff))
        ..add(_u16(addrOff))
        ..add(Uint8List(16)); // ServiceSiteGuid
    }
    at += size;
  }
  return (out..add(strings.takeBytes())).takeBytes();
}

List<int> _u16(int v) => [v & 0xff, v >> 8 & 0xff];
List<int> _u32(int v) => [..._u16(v & 0xffff), ..._u16(v >> 16)];
List<int> _utf16z(String s) => [for (final u in s.codeUnits) ..._u16(u), 0, 0];

/// An in-memory share: '' is its root.
class _FakeShare implements SyncFileSystem {
  final dirs = <String>{};
  final files = <String, Uint8List>{};
  final _open = <int, String>{};
  bool disposed = false;

  Never _missing(String path) =>
      throw VirtualFileException(VirtualFileError.notFound, Uri(path: path));

  @override
  List<VirtualEntry> list(String path) {
    if (!dirs.contains(path)) _missing(path);
    final prefix = path.isEmpty ? '' : '$path/';
    bool direct(String p) =>
        p.startsWith(prefix) &&
        p.isNotEmpty &&
        !p.substring(prefix.length).contains('/');
    return [
      for (final d in dirs.where(direct)) stat(d),
      for (final f in files.keys.where(direct)) stat(f),
    ];
  }

  @override
  VirtualEntry stat(String path) {
    final isDir = dirs.contains(path);
    if (!isDir && !files.containsKey(path)) _missing(path);
    return VirtualEntry(
      uri: Uri(path: '/target/$path'),
      name: path.split('/').last,
      isDirectory: isDir,
      size: isDir ? null : files[path]!.length,
    );
  }

  @override
  int open(String path, {bool write = false, bool create = false}) {
    if (!files.containsKey(path)) _missing(path);
    final id = _open.length + 1;
    _open[id] = path;
    return id;
  }

  @override
  int? length(int handle) => files[_open[handle]]?.length;

  @override
  Uint8List read(int handle, int offset, int length) {
    final f = files[_open[handle]]!;
    final end = (offset + length).clamp(0, f.length);
    return Uint8List.sublistView(f, offset.clamp(0, f.length), end);
  }

  @override
  void write(int handle, int offset, List<int> bytes) =>
      throw UnsupportedError('write');

  @override
  void close(int handle) => _open.remove(handle);

  @override
  void mkdir(String path) => dirs.add(path);

  @override
  void rename(String from, String to) {
    files[to] = files.remove(from) ?? _missing(from);
  }

  @override
  void unlink(String path) => files.remove(path);

  @override
  void rmdir(String path) => dirs.remove(path);

  @override
  void dispose() => disposed = true;
}

/// The DFS root share: `linked` is a link to \nas\public.
final class _FakeRoot extends _FakeShare implements DfsCapableFileSystem {
  _FakeRoot(this.options);

  @override
  final SmbOptions options;
  bool _notCovered = false;
  bool refuse = false;
  int referrals = 0;

  void _checkLink(String path) {
    if (path.split('/').first.toLowerCase() == 'linked') {
      _notCovered = true;
      throw VirtualFileException(VirtualFileError.io, Uri(path: path));
    }
  }

  @override
  List<VirtualEntry> list(String path) {
    _checkLink(path);
    return super.list(path);
  }

  @override
  VirtualEntry stat(String path) {
    _checkLink(path);
    return super.stat(path);
  }

  @override
  int open(String path, {bool write = false, bool create = false}) {
    _checkLink(path);
    return super.open(path, write: write, create: create);
  }

  @override
  bool takePathNotCovered() {
    final v = _notCovered;
    _notCovered = false;
    return v;
  }

  @override
  Uint8List dfsReferral(Uint8List request) {
    referrals++;
    if (refuse) {
      throw VirtualFileException(VirtualFileError.unsupported, Uri());
    }
    return referral([(3, r'\NAS\dfs\linked', r'\nas\public')], consumed: 30);
  }
}
