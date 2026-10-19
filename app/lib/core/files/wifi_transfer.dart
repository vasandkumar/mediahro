import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mediahro/core/net/persistent_network_policy.dart'
    show isLocalNetworkHost;
import 'package:mediahro/core/parsers/xml_lite.dart' show xmlEscape;
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:qr/qr.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Localised text of the transfer web page (from the sources ARB fragment).
@immutable
final class TransferPageStrings {
  const TransferPageStrings({
    required this.title,
    required this.upload,
    required this.download,
    required this.empty,
    required this.uploaded,
  });

  final String title;
  final String upload;
  final String download;
  final String empty;
  final String uploaded;
}

/// Wi-Fi transfer (FILE-005): a web page on the LAN to upload into and
/// download from one folder, behind a random per-session token. Off until
/// the user starts it; stops after [idleTimeout] without requests.
final class WifiTransferServer {
  WifiTransferServer({
    required this.fileSystem,
    required this.folder,
    required this.strings,
    this.idleTimeout = const Duration(minutes: 15),
    this.maxUploadBytes = 64 << 30,
    Random? random,
  }) : token = _token(random ?? Random.secure());

  final MutableFileSystem fileSystem;

  /// Folder shared by the page (a source folder or the app's inbox).
  final Uri folder;
  final TransferPageStrings strings;
  final Duration idleTimeout;
  final int maxUploadBytes;

  /// 128-bit random path secret; a request without it gets a plain 404.
  final String token;

  HttpServer? _server;
  Timer? _idle;
  final _events = StreamController<String>.broadcast();

  /// File names uploaded by browsers (the UI rescans and shows a snackbar).
  Stream<String> get uploads => _events.stream;

  bool get isRunning => _server != null;

  /// Address to show and encode in the QR code.
  Uri get url =>
      Uri(scheme: 'http', host: _host, port: _server!.port, path: '/$token/');
  late String _host;

  Future<Uri> start({InternetAddress? address, int port = 0}) async {
    if (_server != null) return url;
    final addr = address ?? await _lanAddress();
    _host = addr.address;
    _server = await shelf_io.serve(_handle, addr, port);
    _touch();
    return url;
  }

  Future<void> stop() async {
    _idle?.cancel();
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(idleTimeout, () => unawaited(stop()));
  }

  Future<Response> _handle(Request req) async {
    final segs = req.url.pathSegments;
    if (segs.isEmpty || !_constantTimeEquals(segs.first, token)) {
      return Response.notFound('');
    }
    _touch();
    final rest = segs.skip(1).where((s) => s.isNotEmpty).toList();
    try {
      if (req.method == 'GET' && rest.isEmpty) return await _page();
      if (req.method == 'GET' && rest.length == 1 && rest.first == 'files') {
        return await _filesJson();
      }
      if (req.method == 'GET' && rest.length >= 2 && rest.first == 'd') {
        return await _download(rest.sublist(1));
      }
      if (req.method == 'POST' && rest.length == 1 && rest.first == 'upload') {
        return await _upload(req);
      }
    } on VirtualFileException catch (e) {
      return e.error == VirtualFileError.notFound
          ? Response.notFound('')
          : Response.internalServerError();
    }
    return Response.notFound('');
  }

  Future<List<VirtualEntry>> _entries() async =>
      (await fileSystem.list(folder).toList())
          .where((e) => !e.isDirectory && !e.name.startsWith('.'))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<Response> _filesJson() async => Response.ok(
    jsonEncode([
      for (final e in await _entries()) {'name': e.name, 'size': e.size},
    ]),
    headers: {'content-type': 'application/json'},
  );

  Future<Response> _page() async {
    final files = await _entries();
    final rows = files.isEmpty
        ? '<li>${xmlEscape(strings.empty)}</li>'
        : files
              .map(
                (e) =>
                    '<li><a href="d/${Uri.encodeComponent(e.name)}" download>${xmlEscape(e.name)}</a></li>',
              )
              .join();
    final html =
        '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>${xmlEscape(strings.title)}</title>
<style>body{font:16px system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem}li{margin:.4rem 0}</style>
</head><body><h1>${xmlEscape(strings.title)}</h1>
<form method="post" action="upload" enctype="multipart/form-data">
<input type="file" name="file" multiple required> <button>${xmlEscape(strings.upload)}</button></form>
<h2>${xmlEscape(strings.download)}</h2><ul>$rows</ul></body></html>''';
    return Response.ok(
      html,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'content-security-policy':
            "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'",
        'x-frame-options': 'DENY',
        'cache-control': 'no-store',
      },
    );
  }

  Future<Response> _download(List<String> path) async {
    final name = path.join('/');
    final safe = _safeName(name);
    if (safe == null || safe != name) return Response.notFound('');
    final uri = folder.resolve(Uri.encodeComponent(safe));
    final f = await fileSystem.open(uri);
    final len = await f.length();
    final body = () async* {
      var off = 0;
      try {
        while (true) {
          final c = await f.read(off, 1 << 20);
          if (c.isEmpty) break;
          off += c.length;
          yield c;
        }
      } finally {
        await f.close();
      }
    }();
    return Response.ok(
      body,
      headers: {
        'content-type': lookupMimeType(safe) ?? 'application/octet-stream',
        'content-length': ?len?.toString(),
        'content-disposition':
            "attachment; filename*=UTF-8''${Uri.encodeComponent(safe)}",
      },
    );
  }

  Future<Response> _upload(Request req) async {
    final type = req.headers['content-type'] ?? '';
    final boundary = RegExp(r'boundary=("?)([^";]+)\1')
        .firstMatch(type)
        ?.group(2);
    if (!type.startsWith('multipart/form-data') || boundary == null) {
      return Response(400);
    }
    final names = <String>[];
    var total = 0;
    await for (final part in req.read().cast<List<int>>().transform(
      MimeMultipartTransformer(boundary),
    )) {
      final disp = part.headers['content-disposition'] ?? '';
      final raw = RegExp('filename="([^"]*)"').firstMatch(disp)?.group(1);
      final name = raw == null
          ? null
          : _safeName(raw.split(RegExp(r'[\\/]')).last);
      if (name == null) {
        await part.drain<void>();
        continue;
      }
      final w = await fileSystem.create(
        folder.resolve(Uri.encodeComponent(name)),
      );
      try {
        await for (final chunk in part) {
          total += chunk.length;
          if (total > maxUploadBytes) {
            throw const FormatException('upload too large');
          }
          await w.write(chunk);
        }
        await w.close();
        names.add(name);
        _events.add(name);
      } on Object {
        await w.abort();
        return Response(413);
      }
    }
    // Back to the page so the browser shows the new list.
    return Response.found('./', headers: {'x-uploaded': '${names.length}'});
  }

  static String? _safeName(String raw) {
    final n = raw.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*\\/]'), '_').trim();
    if (n.isEmpty || n == '.' || n == '..' || n.startsWith('.')) return null;
    return n.length > 200 ? n.substring(0, 200) : n;
  }

  static String _token(Random r) => List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  static Future<InternetAddress> _lanAddress() async {
    for (final i in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in i.addresses) {
        if (!a.isLoopback && isLocalNetworkHost(a.address)) return a;
      }
    }
    return InternetAddress.loopbackIPv4;
  }
}

/// QR modules for [data] (true = dark), for the transfer page's code.
List<List<bool>> qrModules(String data) {
  final img = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  return [
    for (var r = 0; r < img.moduleCount; r++)
      [for (var c = 0; c < img.moduleCount; c++) img.isDark(r, c)],
  ];
}
