import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages, test-only digest verification
import 'package:crypto/crypto.dart';

/// A minimal WebDAV server over an in-memory tree for client tests:
/// PROPFIND (depth 0/1), GET with Range, PUT, MKCOL, MOVE, DELETE, and
/// optional Digest (MD5, qop=auth) or Basic authentication.
final class TestDavServer {
  TestDavServer._(this._server, {this.user, this.password, this.digest = true});

  static Future<TestDavServer> start({
    String? user,
    String? password,
    bool digest = true,
    String prefix = '/dav',
  }) async {
    final s = TestDavServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      user: user,
      password: password,
      digest: digest,
    ).._prefix = prefix;
    s._server.listen(s._handle);
    return s;
  }

  final HttpServer _server;
  final String? user;
  final String? password;
  final bool digest;
  late final String _prefix;

  /// path (decoded, no prefix, no leading slash) → bytes; folders end in `/`.
  final Map<String, Uint8List> files = {};
  final Set<String> dirs = {''};
  final requests = <String>[];
  int rangeRequests = 0;

  Uri get root => Uri.parse('dav://127.0.0.1:${_server.port}$_prefix/');

  void put(String path, List<int> bytes) {
    files[path] = Uint8List.fromList(bytes);
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      dirs.add(parts.sublist(0, i).join('/'));
    }
  }

  Future<void> close() => _server.close(force: true);

  String _rel(Uri u) {
    var p = Uri.decodeFull(u.path);
    if (!p.startsWith(_prefix)) return '\u0000';
    p = p.substring(_prefix.length);
    if (p.startsWith('/')) p = p.substring(1);
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  bool _authorized(HttpRequest r) {
    if (user == null) return true;
    final h = r.headers.value('authorization');
    if (h == null) return false;
    if (!digest && h.startsWith('Basic ')) {
      return utf8.decode(base64Decode(h.substring(6))) == '$user:$password';
    }
    if (digest && h.startsWith('Digest ')) {
      final m = <String, String>{};
      for (final part in RegExp(
        r'(\w+)=("([^"]*)"|[^,]+)',
      ).allMatches(h.substring(7))) {
        m[part.group(1)!] = part.group(3) ?? part.group(2)!;
      }
      String md(String s) => md5.convert(utf8.encode(s)).toString();
      final ha1 = md('$user:test:$password');
      final ha2 = md('${r.method}:${m['uri']}');
      final expected = md(
        '$ha1:${m['nonce']}:${m['nc']}:${m['cnonce']}:${m['qop']}:$ha2',
      );
      return m['response'] == expected && m['nonce'] == 'n0nce';
    }
    return false;
  }

  Future<void> _handle(HttpRequest r) async {
    requests.add('${r.method} ${r.uri.path}');
    final res = r.response;
    if (!_authorized(r)) {
      res.statusCode = 401;
      res.headers.set(
        'www-authenticate',
        digest
            ? 'Digest realm="test", nonce="n0nce", qop="auth", algorithm=MD5'
            : 'Basic realm="test"',
      );
      await r.drain<void>();
      await res.close();
      return;
    }
    final rel = _rel(r.uri);
    switch (r.method) {
      case 'PROPFIND':
        await r.drain<void>();
        final depth = r.headers.value('depth') ?? '1';
        if (!files.containsKey(rel) && !dirs.contains(rel)) {
          res.statusCode = 404;
          break;
        }
        final b = StringBuffer(
          '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">',
        );
        void entry(String path, {required bool dir}) {
          final href =
              '$_prefix/${path.split('/').map(Uri.encodeComponent).join('/')}${dir && path.isNotEmpty ? '/' : ''}';
          final type = dir
              ? '<D:resourcetype><D:collection/></D:resourcetype>'
              : '<D:resourcetype/>';
          final length = dir
              ? ''
              : '<D:getcontentlength>${files[path]!.length}</D:getcontentlength>';
          b.write(
            [
              '<D:response><D:href>$href</D:href><D:propstat><D:prop>',
              type,
              length,
              '<D:getlastmodified>Mon, 19 Oct 2026 10:00:00 GMT</D:getlastmodified>',
              '</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>',
            ].join(),
          );
        }

        final isDir = dirs.contains(rel);
        entry(rel, dir: isDir);
        if (isDir && depth == '1') {
          final prefix = rel.isEmpty ? '' : '$rel/';
          for (final d in dirs) {
            if (d.startsWith(prefix) &&
                d != rel &&
                !d.substring(prefix.length).contains('/')) {
              entry(d, dir: true);
            }
          }
          for (final f in files.keys) {
            if (f.startsWith(prefix) &&
                !f.substring(prefix.length).contains('/')) {
              entry(f, dir: false);
            }
          }
        }
        b.write('</D:multistatus>');
        res.statusCode = 207;
        res.headers.contentType = ContentType(
          'application',
          'xml',
          charset: 'utf-8',
        );
        res.write(b);
      case 'GET':
        final f = files[rel];
        if (f == null) {
          res.statusCode = 404;
          break;
        }
        res.headers.set('accept-ranges', 'bytes');
        final range = r.headers.value('range');
        if (range != null) {
          rangeRequests++;
          final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
          final start = int.parse(m.group(1)!);
          var end = m.group(2)!.isEmpty ? f.length - 1 : int.parse(m.group(2)!);
          if (start >= f.length) {
            res.statusCode = 416;
            break;
          }
          if (end >= f.length) end = f.length - 1;
          res.statusCode = 206;
          res.headers.set('content-range', 'bytes $start-$end/${f.length}');
          res.add(f.sublist(start, end + 1));
        } else {
          res.add(f);
        }
      case 'PUT':
        final b = BytesBuilder();
        await r.forEach(b.add);
        put(rel, b.takeBytes());
        res.statusCode = 201;
      case 'MKCOL':
        await r.drain<void>();
        if (dirs.contains(rel) || files.containsKey(rel)) {
          res.statusCode = 405;
        } else {
          dirs.add(rel);
          res.statusCode = 201;
        }
      case 'MOVE':
        await r.drain<void>();
        final dest = _rel(Uri.parse(r.headers.value('destination')!));
        if ((files.containsKey(dest) || dirs.contains(dest)) &&
            r.headers.value('overwrite') == 'F') {
          res.statusCode = 412;
          break;
        }
        if (files.containsKey(rel)) {
          files[dest] = files.remove(rel)!;
        } else if (dirs.remove(rel)) {
          dirs.add(dest);
          for (final k
              in files.keys.where((k) => k.startsWith('$rel/')).toList()) {
            files['$dest${k.substring(rel.length)}'] = files.remove(k)!;
          }
        } else {
          res.statusCode = 404;
          break;
        }
        res.statusCode = 201;
      case 'DELETE':
        await r.drain<void>();
        if (files.remove(rel) == null && !dirs.remove(rel)) {
          res.statusCode = 404;
        } else {
          files.removeWhere((k, _) => k.startsWith('$rel/'));
          dirs.removeWhere((k) => k.startsWith('$rel/'));
          res.statusCode = 204;
        }
      default:
        res.statusCode = 405;
    }
    await res.close();
  }
}
