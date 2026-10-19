// XML and SOAP templates are concatenated without separators on purpose.
// ignore_for_file: missing_whitespace_between_adjacent_strings
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/tables.dart';
import 'package:mediahro/core/sources/discovery/lan_discovery.dart';
import 'package:mediahro/core/sources/discovery/mdns.dart';

List<int> _name(String n) => [
  for (final l in n.split('.')) ...[l.length, ...utf8.encode(l)],
  0,
];

List<int> _rr(String name, int type, List<int> data) => [
  ..._name(name),
  type >> 8, type & 0xff, 0x00, 0x01, 0, 0, 0x11, 0x94, //
  data.length >> 8, data.length & 0xff, ...data,
];

Uint8List _response() {
  final answers = [
    _rr('_smb._tcp.local', 12, _name('Living Room NAS._smb._tcp.local')),
    _rr('Living Room NAS._smb._tcp.local', 33, [
      0,
      0,
      0,
      0,
      0x01,
      0xBD,
      ..._name('nas.local'),
    ]),
    _rr('Living Room NAS._smb._tcp.local', 16, [
      5,
      ...utf8.encode('a=b c'),
      4,
      ...utf8.encode('flag'),
    ]),
    _rr('nas.local', 1, [192, 168, 1, 20]),
    _rr('_webdav._tcp.local', 12, _name('Cloud._webdav._tcp.local')),
    _rr('Cloud._webdav._tcp.local', 33, [
      0,
      0,
      0,
      0,
      0x1F,
      0x90,
      ..._name('cloud.local'),
    ]),
    _rr('Cloud._webdav._tcp.local', 16, [11, ...utf8.encode('path=/dav/x')]),
  ];
  return Uint8List.fromList([
    0, 0, 0x84, 0, 0, 0, 0, answers.length, 0, 0, 0, 0, //
    for (final a in answers) ...a,
  ]);
}

void main() {
  test('NET-001 DNS-SD browse resolves PTR, SRV, TXT and A records', () async {
    final responder = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    responder.listen((e) {
      final d = responder.receive();
      if (d != null) responder.send(_response(), d.address, d.port);
    });
    addTearDown(responder.close);
    final found = await browseDnsSd(
      ['_smb._tcp', '_webdav._tcp'],
      timeout: const Duration(milliseconds: 400),
      target: InternetAddress.loopbackIPv4,
      port: responder.port,
    ).toList();
    final smb = found.firstWhere((s) => s.type == '_smb._tcp');
    expect(smb.instance, 'Living Room NAS');
    expect(
      (smb.host, smb.port, smb.connectHost),
      ('nas.local', 445, '192.168.1.20'),
    );
    expect(smb.txt, {'a': 'b c', 'flag': ''});
    final dav = found.firstWhere((s) => s.type == '_webdav._tcp');
    expect(dav.txt['path'], '/dav/x');
    expect(dav.connectHost, 'cloud.local', reason: 'no A record: use the name');
  });

  test(
    'NET-001 malformed DNS packets are rejected (pointer loops, truncation)',
    () {
      final loop = Uint8List.fromList([
        0,
        0,
        0x84,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0xC0,
        12,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(() => decodeDnsRecords(loop), throwsA(isA<DnsFormatException>()));
      expect(
        () => decodeDnsRecords(Uint8List(5)),
        throwsA(isA<DnsFormatException>()),
      );
      expect(encodeMdnsQuery('_smb._tcp.local').sublist(12, 17), [
        4,
        0x5F,
        0x73,
        0x6D,
        0x62,
      ]);
    },
  );

  test(
    'NET-001 WS-Discovery finds Windows hosts from ProbeMatches XAddrs',
    () async {
      final responder = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      responder.listen((e) {
        final d = responder.receive();
        if (d == null) return;
        responder.send(
          utf8.encode(
            '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">'
            '<s:Body><d:ProbeMatches><d:ProbeMatch><d:XAddrs>http://192.168.1.33:5357/abc http://[fe80::1]:5357/abc</d:XAddrs>'
            '</d:ProbeMatch></d:ProbeMatches></s:Body></s:Envelope>',
          ),
          d.address,
          d.port,
        );
      });
      addTearDown(responder.close);
      final hosts = await wsDiscovery(
        timeout: const Duration(milliseconds: 300),
        target: InternetAddress.loopbackIPv4,
        port: responder.port,
      ).toList();
      expect(hosts, [('192.168.1.33', null)]);
    },
  );

  test('NET-001 NetBIOS node status yields the file-server name', () {
    final q = nodeStatusQuery(0x1234);
    expect(q.length, 50);
    final names = [
      [...latin1.encode('WORKGROUP'.padRight(15)), 0x00, 0x84, 0x00],
      [...latin1.encode('OLDNAS'.padRight(15)), 0x20, 0x04, 0x00],
    ];
    final resp = Uint8List.fromList([
      0x12, 0x34, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, //
      ...q.sublist(12, 46),
      0, 0x21, 0, 1, 0, 0, 0, 0, 0, 0x60,
      names.length,
      for (final n in names) ...n,
    ]);
    expect(parseNodeStatus(resp), 'OLDNAS');
  });

  test('NET-001 discovered shares map to source URIs', () {
    const s = DiscoveredShare(
      kind: SourceKind.webdav,
      name: 'Cloud',
      host: '10.0.0.5',
      port: 8080,
      path: '/dav/',
    );
    expect(s.uri.toString(), 'dav://10.0.0.5:8080/dav/');
    const smb = DiscoveredShare(
      kind: SourceKind.smb,
      name: 'NAS',
      host: '10.0.0.6',
    );
    expect(smb.uri.toString(), 'smb://10.0.0.6/');
  });
}
