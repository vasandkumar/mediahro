import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/files/wifi_transfer.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

const _strings = TransferPageStrings(
  title: 'Transfer to Mediahro',
  upload: 'Upload',
  download: 'Files',
  empty: 'No files yet',
  uploaded: 'Uploaded',
);

void main() {
  late Directory dir;
  late WifiTransferServer server;
  late HttpClient http;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mediahro_wifi');
    File('${dir.path}/existing.mp3').writeAsBytesSync([1, 2, 3]);
    server = WifiTransferServer(
      fileSystem: const LocalFileSystem(),
      folder: dir.uri,
      strings: _strings,
    );
    await server.start(address: InternetAddress.loopbackIPv4);
    http = HttpClient();
  });
  tearDown(() async {
    http.close(force: true);
    await server.dispose();
    await dir.delete(recursive: true);
  });

  Future<(int, String)> get(Uri u) async {
    final r = await (await http.getUrl(u)).close();
    return (r.statusCode, await utf8.decodeStream(r));
  }

  test('FILE-005 page and listing need the session token', () async {
    final (status, html) = await get(server.url);
    expect(status, 200);
    expect(html, contains('Transfer to Mediahro'));
    expect(html, contains('existing.mp3'));
    final wrong = server.url.replace(
      path: '/0123456789abcdef0123456789abcdef/',
    );
    expect((await get(wrong)).$1, 404);
    expect((await get(server.url.replace(path: '/'))).$1, 404);
    expect(server.token, hasLength(32));
    final (s2, json) = await get(server.url.resolve('files'));
    expect(s2, 200);
    expect(jsonDecode(json), [
      {'name': 'existing.mp3', 'size': 3},
    ]);
  });

  test('FILE-005 browser upload (multipart) and download', () async {
    final names = <String>[];
    final sub = server.uploads.listen(names.add);
    final req = await http.postUrl(server.url.resolve('upload'));
    const b = 'XyZ123';
    req.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': b},
    );
    req.write(
      '--$b\r\nContent-Disposition: form-data; name="file"; filename="C:\\Users\\me\\holiday clip.mp4"\r\n'
      'Content-Type: video/mp4\r\n\r\nVIDEO-BYTES\r\n'
      '--$b\r\nContent-Disposition: form-data; name="file"; filename="../../evil.sh"\r\n\r\nx\r\n--$b--\r\n',
    );
    final res = await req.close();
    await res.drain<void>();
    expect(res.statusCode, 302);
    expect(
      File('${dir.path}/holiday clip.mp4').readAsStringSync(),
      'VIDEO-BYTES',
    );
    expect(
      File('${dir.path}/evil.sh').existsSync(),
      isTrue,
      reason: 'path parts are stripped',
    );
    expect(File('${dir.parent.path}/evil.sh').existsSync(), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(names, ['holiday clip.mp4', 'evil.sh']);
    final dl = await (await http.getUrl(
      server.url.resolve('d/holiday%20clip.mp4'),
    )).close();
    expect(await utf8.decodeStream(dl), 'VIDEO-BYTES');
    expect(
      dl.headers.value('content-disposition'),
      contains('holiday%20clip.mp4'),
    );
    expect((await get(server.url.resolve('d/..%2F..%2Fsecret'))).$1, 404);
    await sub.cancel();
  });

  test('FILE-005 stops after inactivity; QR encodes the URL', () async {
    final short = WifiTransferServer(
      fileSystem: const LocalFileSystem(),
      folder: dir.uri,
      strings: _strings,
      idleTimeout: const Duration(milliseconds: 50),
    );
    await short.start(address: InternetAddress.loopbackIPv4);
    expect(short.isRunning, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(short.isRunning, isFalse);
    await short.dispose();
    final qr = qrModules(server.url.toString());
    expect(qr.length, greaterThanOrEqualTo(21));
    expect(qr.first.length, qr.length);
    expect(qr[0][0], isTrue, reason: 'finder pattern corner');
  });
}
