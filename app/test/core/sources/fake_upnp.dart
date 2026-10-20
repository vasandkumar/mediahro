// XML and SOAP templates are concatenated without separators on purpose.
// ignore_for_file: missing_whitespace_between_adjacent_strings
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mediahro/core/parsers/xml_lite.dart';

/// A fake DLNA media server: SSDP responder on loopback, description,
/// ContentDirectory Browse with paging, and media resources over HTTP.
final class FakeMediaServer {
  FakeMediaServer._(this._http, this._udp);

  static Future<FakeMediaServer> start() async {
    final s = FakeMediaServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    s._http.listen(s._handle);
    s._udp.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s._udp.receive();
      if (d == null) return;
      final text = latin1.decode(d.data);
      if (!text.startsWith('M-SEARCH')) return;
      s.searches++;
      s._udp.send(
        latin1.encode(
          'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\n'
          'LOCATION: ${s.location}\r\nST: urn:schemas-upnp-org:device:MediaServer:1\r\n'
          'USN: uuid:fake-1::urn:schemas-upnp-org:device:MediaServer:1\r\n\r\n',
        ),
        d.address,
        d.port,
      );
    });
    return s;
  }

  final HttpServer _http;
  final RawDatagramSocket _udp;
  int searches = 0;
  int browses = 0;

  /// containerId → children (id, title, isContainer, mediaPath?).
  final Map<String, List<(String, String, bool, String?)>> tree = {
    '0': [('1', 'Video', true, null), ('2', 'Music', true, null)],
    '1': [
      ('11', 'Movie', false, '/media/movie.mkv'),
      ('12', 'Movie', false, '/media/movie2.mkv'),
      ('13', 'Clip & Co', false, '/media/clip.mp4'),
    ],
    '2': [
      for (var i = 0; i < 5; i++) ('2$i', 'Song $i', false, '/media/s$i.mp3'),
    ],
  };
  final List<int> media = List.generate(4096, (i) => i % 256);

  int get ssdpPort => _udp.port;
  Uri get location => Uri.parse('http://127.0.0.1:${_http.port}/desc.xml');

  Future<void> close() async {
    _udp.close();
    await _http.close(force: true);
  }

  Future<void> _handle(HttpRequest r) async {
    final res = r.response;
    switch (r.uri.path) {
      case '/desc.xml':
        res.headers.contentType = ContentType('text', 'xml');
        res.write(
          '<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0">'
          '<specVersion><major>1</major><minor>0</minor></specVersion><device>'
          '<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
          '<friendlyName>Fake NAS</friendlyName><UDN>uuid:fake-1</UDN><manufacturer>Test</manufacturer>'
          '<iconList><icon><mimetype>image/png</mimetype><width>120</width><height>120</height><url>/icon.png</url></icon></iconList>'
          '<serviceList><service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>'
          '<serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId><controlURL>/cd/control</controlURL>'
          '<eventSubURL>/cd/event</eventSubURL><SCPDURL>/cd/scpd.xml</SCPDURL></service></serviceList>'
          '</device></root>',
        );
      case '/cd/control':
        // Like MiniDLNA: no chunked request bodies on the control URL.
        if (r.headers.chunkedTransferEncoding || r.contentLength < 0) {
          res.statusCode = HttpStatus.badRequest;
          break;
        }
        browses++;
        final body = await utf8.decodeStream(r);
        final env = parseXml(body);
        final browse = env.descendants('Browse').first;
        final id = browse.childText('ObjectID')!;
        final start = int.parse(browse.childText('StartingIndex')!);
        final count = int.parse(browse.childText('RequestedCount')!);
        final kids = tree[id];
        if (kids == null) {
          res
            ..statusCode = 500
            ..write(
              '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
              '<detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>701</errorCode>'
              '<errorDescription>No such object</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>',
            );
          break;
        }
        final page = kids.skip(start).take(count).toList();
        final didl = StringBuffer(
          '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">',
        );
        for (final (cid, title, isC, path) in page) {
          if (isC) {
            didl.write(
              '<container id="$cid" parentID="$id" restricted="1"><dc:title>${xmlEscape(title)}</dc:title>'
              '<upnp:class>object.container.storageFolder</upnp:class></container>',
            );
          } else {
            didl.write(
              '<item id="$cid" parentID="$id" restricted="1"><dc:title>${xmlEscape(title)}</dc:title>'
              '<upnp:class>object.item.videoItem</upnp:class>'
              '<res protocolInfo="http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0" size="${media.length}" '
              'duration="0:01:02.500">http://127.0.0.1:${_http.port}$path</res></item>',
            );
          }
        }
        didl.write('</DIDL-Lite>');
        res.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
        res.write(
          '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
          '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
          '<Result>${xmlEscape(didl.toString())}</Result><NumberReturned>${page.length}</NumberReturned>'
          '<TotalMatches>${kids.length}</TotalMatches><UpdateID>1</UpdateID></u:BrowseResponse></s:Body></s:Envelope>',
        );
      default:
        if (r.uri.path.startsWith('/media/')) {
          res.headers.set('accept-ranges', 'bytes');
          final range = r.headers.value('range');
          if (range != null) {
            final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
            final a = int.parse(m.group(1)!);
            final b = m.group(2)!.isEmpty
                ? media.length - 1
                : int.parse(m.group(2)!).clamp(0, media.length - 1);
            res.statusCode = 206;
            res.headers.set('content-range', 'bytes $a-$b/${media.length}');
            res.add(media.sublist(a, b + 1));
          } else {
            res.add(media);
          }
        } else {
          res.statusCode = 404;
        }
    }
    await res.close();
  }
}
