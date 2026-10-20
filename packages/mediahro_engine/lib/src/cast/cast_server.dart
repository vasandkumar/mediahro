import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Local HTTP server that exposes the current cast item to receivers on the
/// LAN (docs/05 §4.5, CAST-005).
///
/// Inbound only: it never makes a request itself, so it is outside the
/// PRIV-004 outbound allow-list. Every publication lives under an
/// unguessable token path and is removed with [unpublish] or [close].
final class CastServer {
  CastServer._(this._server, this.host);

  final HttpServer _server;

  /// Address receivers use (the LAN interface, or loopback in tests).
  final InternetAddress host;
  final _items = <String, _Published>{};
  final _random = Random.secure();

  int get port => _server.port;

  /// Starts the server on [address] (default: the first LAN IPv4 address)
  /// and an ephemeral [port].
  static Future<CastServer> start({
    InternetAddress? address,
    int port = 0,
  }) async {
    final host = address ?? await lanAddress() ?? InternetAddress.loopbackIPv4;
    late final CastServer server;
    final http = await shelf_io.serve((r) => server._handle(r), host, port);
    http.autoCompress = false;
    return server = CastServer._(http, host);
  }

  /// First non-loopback IPv4 address, or null.
  static Future<InternetAddress?> lanAddress() async {
    for (final i in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.isLinkLocal) return a;
      }
    }
    return null;
  }

  String _token() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Uri _url(String token, String name) => Uri(
    scheme: 'http',
    host: host.address,
    port: port,
    path: '/$token/$name',
  );

  /// Publishes a local file with byte-range support (passthrough).
  Uri publishFile(File file, {String? contentType}) {
    final token = _token();
    final name = file.uri.pathSegments.last;
    _items[token] = _Published.file(file, contentType ?? mimeFor(name));
    return _url(token, Uri.encodeComponent(name));
  }

  /// Publishes a [VirtualFile] (network share, archive entry) with ranges.
  Uri publishVirtualFile(VirtualFile file, String name, {String? contentType}) {
    final token = _token();
    _items[token] = _Published.virtual(file, contentType ?? mimeFor(name));
    return _url(token, Uri.encodeComponent(name));
  }

  /// Publishes a transcoder output directory; [entry] is the playlist or
  /// stream file inside it.
  Uri publishDirectory(Directory dir, String entry) {
    final token = _token();
    _items[token] = _Published.directory(dir);
    return _url(token, entry);
  }

  /// Publishes generated text (WebVTT subtitles).
  Uri publishText(
    String name,
    String body, {
    String contentType = 'text/vtt; charset=utf-8',
  }) {
    final token = _token();
    _items[token] = _Published.text(utf8.encode(body), contentType);
    return _url(token, name);
  }

  void unpublish(Uri url) {
    if (url.pathSegments.isNotEmpty) _items.remove(url.pathSegments.first);
  }

  Future<void> close() async {
    _items.clear();
    await _server.close(force: true);
  }

  static const _cors = {
    // Cast receivers fetch media and WebVTT cross-origin.
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'range, content-type',
    'access-control-expose-headers':
        'content-length, content-range, accept-ranges',
  };

  Future<Response> _handle(Request r) async {
    if (r.method == 'OPTIONS') return Response.ok(null, headers: _cors);
    if (r.method != 'GET' && r.method != 'HEAD') {
      return Response(405, headers: _cors);
    }
    final segs = r.url.pathSegments;
    if (segs.length < 2) return Response.notFound(null, headers: _cors);
    final item = _items[segs.first];
    if (item == null) return Response.notFound(null, headers: _cors);
    final head = r.method == 'HEAD';
    switch (item.kind) {
      case _Kind.text:
        return Response.ok(
          head ? null : item.text,
          headers: {..._cors, 'content-type': item.contentType!},
        );
      case _Kind.directory:
        final name = segs.sublist(1).join('/');
        if (name.contains('..')) {
          return Response.forbidden(null, headers: _cors);
        }
        final f = File('${item.dir!.path}${Platform.pathSeparator}$name');
        if (!f.existsSync()) return Response.notFound(null, headers: _cors);
        return await _ranged(r, head, mimeFor(name), await f.length(), (
          o,
          n,
        ) async {
          final raf = await f.open();
          try {
            await raf.setPosition(o);
            return await raf.read(n);
          } finally {
            await raf.close();
          }
        }, live: name.endsWith('.m3u8') || name.endsWith('.webm'));
      case _Kind.file:
        final f = item.file!;
        return await _ranged(r, head, item.contentType!, await f.length(), (
          o,
          n,
        ) async {
          final raf = await f.open();
          try {
            await raf.setPosition(o);
            return await raf.read(n);
          } finally {
            await raf.close();
          }
        });
      case _Kind.virtual:
        final v = item.virtual!;
        final len = await v.length();
        return await _ranged(r, head, item.contentType!, len, v.read);
    }
  }

  Future<Response> _ranged(
    Request r,
    bool head,
    String type,
    int? length,
    Future<Uint8List> Function(int offset, int length) read, {
    bool live = false,
  }) async {
    final headers = {
      ..._cors,
      'content-type': type,
      if (!live) 'accept-ranges': 'bytes',
      'cache-control': 'no-store',
    };
    final range = RegExp(r'^bytes=(\d*)-(\d*)$')
        .firstMatch(r.headers['range'] ?? '');
    if (range == null || length == null || live) {
      if (length != null) headers['content-length'] = '$length';
      return Response.ok(
        head || length == null ? null : _stream(read, 0, length),
        headers: headers,
      );
    }
    var start = int.tryParse(range.group(1)!);
    var end = int.tryParse(range.group(2)!);
    if (start == null) {
      // Suffix range: last N bytes.
      start = end == null ? 0 : max(0, length - end);
      end = length - 1;
    }
    end = min(end ?? length - 1, length - 1);
    if (start >= length || start > end) {
      return Response(
        416,
        headers: {...headers, 'content-range': 'bytes */$length'},
      );
    }
    final count = end - start + 1;
    return Response(
      206,
      body: head ? null : _stream(read, start, count),
      headers: {
        ...headers,
        'content-length': '$count',
        'content-range': 'bytes $start-$end/$length',
      },
    );
  }

  static Stream<List<int>> _stream(
    Future<Uint8List> Function(int offset, int length) read,
    int start,
    int count,
  ) async* {
    const chunk = 256 * 1024;
    var pos = start;
    var left = count;
    while (left > 0) {
      final data = await read(pos, min(chunk, left));
      if (data.isEmpty) return;
      yield data;
      pos += data.length;
      left -= data.length;
    }
  }
}

/// MIME type for a cast file name.
String mimeFor(String name) {
  final ext = name.toLowerCase().split('.').last;
  return switch (ext) {
    'mp4' || 'm4v' => 'video/mp4',
    'm4a' => 'audio/mp4',
    'webm' => 'video/webm',
    'mkv' => 'video/x-matroska',
    'ts' => 'video/mp2t',
    'm3u8' => 'application/vnd.apple.mpegurl',
    'vtt' => 'text/vtt; charset=utf-8',
    'mp3' => 'audio/mpeg',
    'flac' => 'audio/flac',
    'ogg' || 'opus' => 'audio/ogg',
    'aac' => 'audio/aac',
    'mov' => 'video/quicktime',
    _ => 'application/octet-stream',
  };
}

enum _Kind { file, virtual, directory, text }

final class _Published {
  _Published.file(File this.file, String this.contentType)
    : kind = _Kind.file,
      virtual = null,
      dir = null,
      text = null;
  _Published.virtual(VirtualFile this.virtual, String this.contentType)
    : kind = _Kind.virtual,
      file = null,
      dir = null,
      text = null;
  _Published.directory(Directory this.dir)
    : kind = _Kind.directory,
      file = null,
      virtual = null,
      contentType = null,
      text = null;
  _Published.text(List<int> this.text, String this.contentType)
    : kind = _Kind.text,
      file = null,
      virtual = null,
      dir = null;

  final _Kind kind;
  final File? file;
  final VirtualFile? virtual;
  final Directory? dir;
  final List<int>? text;
  final String? contentType;
}
