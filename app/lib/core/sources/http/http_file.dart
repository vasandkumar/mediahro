import 'dart:async';
import 'dart:typed_data';

import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// A [VirtualFile] over HTTP(S) range requests (NET-003, NET-006, NET-007,
/// docs/05 §9): seekable when the server honours `Range`, with a small
/// block cache so the engine's and parsers' small reads stay cheap.
final class HttpVirtualFile implements VirtualFile {
  HttpVirtualFile._(
    this.uri,
    this._session,
    this._length,
    this.isSeekable, {
    required this.blockSize,
    required this.maxBlocks,
  });

  /// Probes [uri] with a one-byte range request.
  static Future<HttpVirtualFile> open(
    Uri uri,
    HttpSession session, {
    int blockSize = 256 << 10,
    int maxBlocks = 16,
    int? knownLength,
  }) async {
    final res = await session.send(
      'GET',
      uri,
      extra: const {'Range': 'bytes=0-0'},
    );
    await res.body.drain<void>();
    HttpSession.check(res.statusCode, uri);
    var length = knownLength;
    var seekable = false;
    if (res.statusCode == 206) {
      seekable = true;
      final cr = res.headers['content-range'];
      final total = cr == null
          ? null
          : RegExp(r'/(\d+)$').firstMatch(cr)?.group(1);
      length ??= total == null ? null : int.parse(total);
    } else {
      final cl = res.headers['content-length'];
      length ??= cl == null ? null : int.tryParse(cl);
      seekable = res.headers['accept-ranges']?.toLowerCase() == 'bytes';
    }
    return HttpVirtualFile._(
      uri,
      session,
      length,
      seekable,
      blockSize: blockSize,
      maxBlocks: maxBlocks,
    );
  }

  @override
  final Uri uri;
  final HttpSession _session;
  final int? _length;
  @override
  final bool isSeekable;
  final int blockSize;
  final int maxBlocks;
  final _blocks = <int, Uint8List>{};
  final _inflight = <int, Future<Uint8List>>{};
  bool _closed = false;

  /// Bytes fetched from the server (tests, connection health).
  int bytesFetched = 0;

  @override
  Future<int?> length() async => _length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    RangeError.checkNotNegative(offset, 'offset');
    RangeError.checkNotNegative(length, 'length');
    final size = _length;
    var end = offset + length;
    if (size != null && end > size) end = size;
    if (end <= offset) return Uint8List(0);
    if (!isSeekable && offset != 0) {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        uri,
        'server does not support ranges',
      );
    }
    // Large reads bypass the cache.
    if (end - offset > blockSize * 4) return await _range(offset, end - 1);
    final out = BytesBuilder(copy: false);
    for (var b = offset ~/ blockSize; b * blockSize < end; b++) {
      final block = await _block(b);
      final from = b * blockSize;
      final s = offset > from ? offset - from : 0;
      final e = end - from < block.length ? end - from : block.length;
      if (s >= e) break;
      out.add(Uint8List.sublistView(block, s, e));
      if (block.length < blockSize) break;
    }
    return out.takeBytes();
  }

  Future<Uint8List> _block(int index) {
    final cached = _blocks.remove(index);
    if (cached != null) {
      _blocks[index] = cached; // LRU touch
      return Future.value(cached);
    }
    return _inflight[index] ??= () async {
      try {
        final start = index * blockSize;
        var last = start + blockSize - 1;
        final size = _length;
        if (size != null && last >= size) last = size - 1;
        final data = await _range(start, last);
        _blocks[index] = data;
        while (_blocks.length > maxBlocks) {
          _blocks.remove(_blocks.keys.first);
        }
        return data;
      } finally {
        unawaited(_inflight.remove(index));
      }
    }();
  }

  Future<Uint8List> _range(int first, int last) async {
    final res = await _session.send(
      'GET',
      uri,
      extra: {'Range': 'bytes=$first-$last'},
    );
    if (res.statusCode == 416) {
      await res.body.drain<void>();
      return Uint8List(0);
    }
    HttpSession.check(res.statusCode, uri);
    final b = BytesBuilder(copy: false);
    final want = last - first + 1;
    if (res.statusCode == 200) {
      // Server ignored the range: skip to [first].
      var skipped = 0;
      await for (final chunk in res.body) {
        var c = chunk;
        if (skipped < first) {
          final need = first - skipped;
          if (c.length <= need) {
            skipped += c.length;
            continue;
          }
          c = c.sublist(need);
          skipped = first;
        }
        b.add(c);
        if (b.length >= want) break;
      }
    } else {
      await res.body.forEach(b.add);
    }
    final bytes = b.takeBytes();
    bytesFetched += bytes.length;
    return bytes.length > want ? Uint8List.sublistView(bytes, 0, want) : bytes;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _blocks.clear();
  }
}
