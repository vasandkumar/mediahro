import 'dart:typed_data';

import 'package:mediahro_ffi/src/smb2/smb2_client.dart';
import 'package:mediahro_ffi/src/vfs/isolate_file_system.dart';
import 'package:mediahro_ffi/src/vfs/virtual_file.dart';
import 'package:meta/meta.dart';

/// What [SmbDfsFileSystem] needs from the client on the share it wraps.
abstract interface class DfsCapableFileSystem implements SyncFileSystem {
  SmbOptions get options;

  /// Whether the last failed call was answered with STATUS_PATH_NOT_COVERED
  /// (the path crosses a DFS link). Reading it clears it.
  bool takePathNotCovered();

  /// FSCTL_DFS_GET_REFERRALS on this tree: [request] is a
  /// REQ_GET_DFS_REFERRAL, the result the raw RESP_GET_DFS_REFERRAL.
  Uint8List dfsReferral(Uint8List request);
}

/// One target of a DFS referral (MS-DFSC 2.2.5).
@immutable
final class DfsTarget {
  const DfsTarget({
    required this.dfsPath,
    required this.networkAddress,
    this.timeToLive = Duration.zero,
  });

  /// The link the referral answers for, `\server\share\link`.
  final String dfsPath;

  /// Where it points, `\server\share[\path]`.
  final String networkAddress;

  /// How long the client may cache this referral (V2+; zero for V1).
  final Duration timeToLive;
}

/// A parsed RESP_GET_DFS_REFERRAL (MS-DFSC 2.2.4).
@immutable
final class DfsReferral {
  const DfsReferral({required this.pathConsumed, required this.targets});

  /// Bytes (UTF-16) of the request path the link covers.
  final int pathConsumed;
  final List<DfsTarget> targets;
}

/// REQ_GET_DFS_REFERRAL for [uncPath] (`\server\share\path`), asking for up
/// to version 4 referrals.
@visibleForTesting
Uint8List encodeDfsReferralRequest(String uncPath) {
  final units = uncPath.codeUnits;
  final b = ByteData(2 + (units.length + 1) * 2)
    ..setUint16(0, 4, Endian.little);
  for (var i = 0; i < units.length; i++) {
    b.setUint16(2 + i * 2, units[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Parses a RESP_GET_DFS_REFERRAL. Bounded by the buffer (at most 64 KiB
/// from libsmb2) and by [maxReferrals]; throws [FormatException] when an
/// entry or string runs past the end.
@visibleForTesting
DfsReferral parseDfsReferral(Uint8List data, {int maxReferrals = 64}) {
  final b = ByteData.sublistView(data);
  if (b.lengthInBytes < 8) throw const FormatException('short DFS referral');
  final consumed = b.getUint16(0, Endian.little);
  final count = b.getUint16(2, Endian.little);
  if (count > maxReferrals) throw const FormatException('too many referrals');
  final targets = <DfsTarget>[];
  var at = 8;
  for (var i = 0; i < count; i++) {
    if (at + 8 > b.lengthInBytes) {
      throw const FormatException('DFS referral entry past the end');
    }
    final version = b.getUint16(at, Endian.little);
    final size = b.getUint16(at + 2, Endian.little);
    if (size < 8 || at + size > b.lengthInBytes) {
      throw const FormatException('bad DFS referral entry size');
    }
    String str(int offset) => _utf16z(b, at + offset);
    switch (version) {
      case 1:
        targets.add(DfsTarget(dfsPath: '', networkAddress: _utf16z(b, at + 8)));
      case 2:
        if (size < 22) throw const FormatException('short V2 referral');
        targets.add(
          DfsTarget(
            dfsPath: str(b.getUint16(at + 16, Endian.little)),
            networkAddress: str(b.getUint16(at + 20, Endian.little)),
            timeToLive: Duration(seconds: b.getUint32(at + 12, Endian.little)),
          ),
        );
      case 3 || 4:
        if (size < 18) throw const FormatException('short V3/V4 referral');
        // NameListReferral (domain or DC referrals) carry no link target.
        final nameList = b.getUint16(at + 6, Endian.little) & 0x0002 != 0;
        if (!nameList) {
          targets.add(
            DfsTarget(
              dfsPath: str(b.getUint16(at + 12, Endian.little)),
              networkAddress: str(b.getUint16(at + 16, Endian.little)),
              timeToLive: Duration(seconds: b.getUint32(at + 8, Endian.little)),
            ),
          );
        }
      default:
        throw FormatException('unknown DFS referral version $version');
    }
    at += size;
  }
  return DfsReferral(pathConsumed: consumed, targets: targets);
}

String _utf16z(ByteData b, int at) {
  final units = <int>[];
  for (var i = at; ; i += 2) {
    if (i + 2 > b.lengthInBytes) {
      throw const FormatException('unterminated DFS string');
    }
    final u = b.getUint16(i, Endian.little);
    if (u == 0) break;
    units.add(u);
  }
  return String.fromCharCodes(units);
}

List<String> _segments(String path, [String separator = '/']) =>
    path.split(separator).where((s) => s.isNotEmpty).toList();

/// [SyncFileSystem] over an SMB share that follows DFS links (NET-001).
///
/// libsmb2 has no DFS client. When a call at the root is answered with
/// STATUS_PATH_NOT_COVERED, this asks the server for a referral, connects
/// to the target share with the same credentials and serves everything
/// below the link from there. Links are cached for the referral's TTL;
/// targets that are DFS roots themselves are followed up to [maxHops]. A
/// link without a usable referral is reported as notFound.
final class SmbDfsFileSystem implements SyncFileSystem {
  SmbDfsFileSystem(
    this._root, {
    SyncFileSystem Function(SmbOptions options, int hops)? connect,
    DfsCapableFileSystem Function(SmbOptions options)? connectIpc,
    Duration Function()? clock,
    this.maxHops = 4,
    this.hops = 0,
  }) : _connect = connect ?? _defaultConnect,
       _connectIpc = connectIpc ?? Smb2SyncFileSystem.new,
       _clock = clock ?? _monotonic;

  final DfsCapableFileSystem _root;
  final SyncFileSystem Function(SmbOptions options, int hops) _connect;
  final DfsCapableFileSystem Function(SmbOptions options) _connectIpc;

  /// Monotonic time, for referral TTLs.
  final Duration Function() _clock;
  static final Stopwatch _since = Stopwatch()..start();
  static Duration _monotonic() => _since.elapsed;
  final int maxHops;

  /// Links already followed to reach this share.
  final int hops;

  final _links = <_DfsLink>[];
  final _targets = <String, SyncFileSystem>{};
  final _handles = <int, (SyncFileSystem, int)>{};
  int _next = 1;

  static SyncFileSystem _defaultConnect(SmbOptions o, int hops) =>
      SmbDfsFileSystem(Smb2SyncFileSystem(o), hops: hops);

  SmbOptions get _options => _root.options;

  @override
  List<VirtualEntry> list(String path) => _run(path, (fs, p) {
    final entries = fs.list(p);
    if (identical(fs, _root)) return entries;
    return [
      for (final e in entries)
        _rebase(e, [..._segments(path), e.name].join('/')),
    ];
  });

  @override
  VirtualEntry stat(String path) => _run(path, (fs, p) {
    final e = fs.stat(p);
    return identical(fs, _root) ? e : _rebase(e, path);
  });

  @override
  int open(String path, {bool write = false, bool create = false}) =>
      _run(path, (fs, p) {
        final h = fs.open(p, write: write, create: create);
        final id = _next++;
        _handles[id] = (fs, h);
        return id;
      });

  @override
  int? length(int handle) {
    final h = _handles[handle];
    return h?.$1.length(h.$2);
  }

  @override
  Uint8List read(int handle, int offset, int length) {
    final (fs, h) = _handle(handle);
    return fs.read(h, offset, length);
  }

  @override
  void write(int handle, int offset, List<int> bytes) {
    final (fs, h) = _handle(handle);
    fs.write(h, offset, bytes);
  }

  @override
  void close(int handle) {
    final h = _handles.remove(handle);
    if (h != null) h.$1.close(h.$2);
  }

  @override
  void mkdir(String path) => _run(path, (fs, p) => fs.mkdir(p));

  @override
  void unlink(String path) => _run(path, (fs, p) => fs.unlink(p));

  @override
  void rmdir(String path) => _run(path, (fs, p) => fs.rmdir(p));

  @override
  void rename(String from, String to) => _run(from, (fs, f) {
    final (toFs, t) = _route(to) ?? (_root, to);
    if (!identical(toFs, fs)) {
      // A DFS link boundary is a different share: no server-side rename.
      throw VirtualFileException(
        VirtualFileError.unsupported,
        smbUri(_options, from),
        'rename across a DFS link',
      );
    }
    fs.rename(f, t);
  });

  @override
  void dispose() {
    for (final (fs, h) in _handles.values) {
      fs.close(h);
    }
    _handles.clear();
    for (final fs in _targets.values) {
      fs.dispose();
    }
    _targets.clear();
    _links.clear();
    _root.dispose();
  }

  (SyncFileSystem, int) _handle(int handle) =>
      _handles[handle] ??
      (throw VirtualFileException(
        VirtualFileError.closed,
        smbUri(_options, ''),
      ));

  /// Runs [op] on whichever file system serves [path]: the root share
  /// unless [path] is below a link.
  T _run<T>(String path, T Function(SyncFileSystem fs, String p) op) {
    final routed = _route(path);
    if (routed != null) return op(routed.$1, routed.$2);
    try {
      return op(_root, path);
    } on VirtualFileException catch (e) {
      if (!_root.takePathNotCovered()) rethrow;
      if (!_resolve(path)) {
        // The server says the path is behind a link but gives no referral
        // we can follow: for the user, it is not there.
        throw VirtualFileException(VirtualFileError.notFound, e.uri, e.detail);
      }
    }
    // Fresh: a zero TTL still serves the call that asked for it.
    final (fs, p) = _route(path, fresh: true)!;
    return op(fs, p);
  }

  /// The file system and path serving [path], when it is below a known,
  /// unexpired link. An expired link is forgotten: the next call at the
  /// root gets PATH_NOT_COVERED again and asks for a new referral.
  (SyncFileSystem, String)? _route(String path, {bool fresh = false}) {
    if (!fresh) {
      final now = _clock();
      _links.removeWhere((l) => now >= l.expires);
    }
    final segs = _segments(path);
    _DfsLink? best;
    for (final l in _links) {
      if (l.prefix.length > segs.length) continue;
      if (best != null && l.prefix.length <= best.prefix.length) continue;
      var match = true;
      for (var i = 0; i < l.prefix.length; i++) {
        if (l.prefix[i] != segs[i].toLowerCase()) {
          match = false;
          break;
        }
      }
      if (match) best = l;
    }
    if (best == null) return null;
    return (
      best.target,
      [...best.base, ...segs.skip(best.prefix.length)].join('/'),
    );
  }

  /// Asks for a referral for [path] and records the link. False when the
  /// server gave none that we can follow (the caller rethrows the original
  /// error).
  bool _resolve(String path) {
    if (hops >= maxHops) return false;
    final segs = _segments(path);
    final unc = '\\${_options.server}\\${_options.share}\\${segs.join(r'\')}';
    final request = encodeDfsReferralRequest(unc);
    final DfsReferral ref;
    try {
      ref = parseDfsReferral(_referral(request));
    } on VirtualFileException {
      return false;
    } on FormatException {
      return false;
    }
    for (final t in ref.targets) {
      final prefix = _linkPrefix(t.dfsPath, ref.pathConsumed, unc, segs);
      final target = _segments(t.networkAddress, r'\');
      if (prefix == null || prefix.isEmpty || target.length < 2) continue;
      final SyncFileSystem fs;
      try {
        fs = _target(target[0], target[1]);
      } on VirtualFileException {
        continue;
      }
      final link = [for (final s in prefix) s.toLowerCase()];
      _links
        ..removeWhere((l) => _sameSegments(l.prefix, link))
        ..add(
          _DfsLink(
            prefix: link,
            target: fs,
            base: target.sublist(2),
            expires: _clock() + t.timeToLive,
          ),
        );
      return true;
    }
    return false;
  }

  /// Asked of IPC$ (MS-DFSC 3.1.4.1), then of the root share's own tree
  /// for servers that refuse an IPC$ session to this user.
  Uint8List _referral(Uint8List request) {
    try {
      final o = _options;
      final ipc = _connectIpc(
        SmbOptions(
          server: o.server,
          share: r'IPC$',
          user: o.user,
          password: o.password,
          domain: o.domain,
          port: o.port,
          guest: o.guest,
          version: o.version,
          encrypt: o.encrypt,
          sign: o.sign,
          timeout: o.timeout,
          workstation: o.workstation,
        ),
      );
      try {
        return ipc.dfsReferral(request);
      } finally {
        ipc.dispose();
      }
    } on VirtualFileException {
      return _root.dfsReferral(request);
    }
  }

  /// The link's path segments inside this share: from the referral's DFS
  /// path when it names this share, else from PathConsumed (UTF-16 bytes
  /// of [unc]).
  static List<String>? _linkPrefix(
    String dfsPath,
    int pathConsumed,
    String unc,
    List<String> segs,
  ) {
    final fromDfs = _segments(dfsPath, r'\');
    if (fromDfs.length > 2) {
      final link = fromDfs.sublist(2);
      if (link.length <= segs.length &&
          [
            for (var i = 0; i < link.length; i++)
              link[i].toLowerCase() == segs[i].toLowerCase(),
          ].every((m) => m)) {
        return link;
      }
    }
    final chars = pathConsumed ~/ 2;
    if (chars <= 0 || chars > unc.length) return null;
    final link = _segments(unc.substring(0, chars), r'\');
    return link.length > 2 ? link.sublist(2) : null;
  }

  SyncFileSystem _target(String server, String share) {
    final key = '${server.toLowerCase()}\\${share.toLowerCase()}';
    final known = _targets[key];
    if (known != null) return known;
    final o = _options;
    final fs = _connect(
      SmbOptions(
        server: server,
        share: share,
        user: o.user,
        password: o.password,
        domain: o.domain,
        // Same server: same (possibly forwarded) port.
        port: server.toLowerCase() == o.server.toLowerCase() ? o.port : null,
        guest: o.guest,
        version: o.version,
        encrypt: o.encrypt,
        sign: o.sign,
        timeout: o.timeout,
        workstation: o.workstation,
      ),
      hops + 1,
    );
    return _targets[key] = fs;
  }

  VirtualEntry _rebase(VirtualEntry e, String path) => VirtualEntry(
    uri: smbUri(_options, path, directory: e.isDirectory),
    name: _segments(path).lastOrNull ?? '',
    isDirectory: e.isDirectory,
    size: e.size,
    modified: e.modified,
  );
}

bool _sameSegments(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((m) => m);

final class _DfsLink {
  _DfsLink({
    required this.prefix,
    required this.target,
    required this.base,
    required this.expires,
  });

  /// When the referral's TTL runs out (on the [SmbDfsFileSystem] clock).
  final Duration expires;

  /// Lower-cased path segments of the link inside the root share.
  final List<String> prefix;
  final SyncFileSystem target;

  /// Path segments inside the target share the link points at.
  final List<String> base;
}
