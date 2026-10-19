// XML and SOAP templates are concatenated without separators on purpose.
// ignore_for_file: missing_whitespace_between_adjacent_strings
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mediahro/core/db/tables.dart';
import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:mediahro/core/sources/discovery/mdns.dart';
import 'package:meta/meta.dart';

/// A share host found on the LAN, for the "Add network share" list
/// (docs/06 §3.4).
@immutable
final class DiscoveredShare {
  const DiscoveredShare({
    required this.kind,
    required this.name,
    required this.host,
    this.port,
    this.path,
    this.via = '',
  });

  final SourceKind kind;
  final String name;
  final String host;
  final int? port;

  /// e.g. the WebDAV path from the TXT record.
  final String? path;

  /// `mdns`, `wsd`, `netbios`, `ssdp` (shown as a secondary label).
  final String via;

  Uri get uri => Uri(
    scheme: switch (kind) {
      SourceKind.smb => 'smb',
      SourceKind.nfs => 'nfs',
      SourceKind.webdav => port == 443 ? 'davs' : 'dav',
      SourceKind.ftp => 'ftp',
      SourceKind.sftp => 'sftp',
      _ => kind.name,
    },
    host: host,
    port: port,
    path: path ?? '/',
  );

  @override
  bool operator ==(Object other) =>
      other is DiscoveredShare &&
      other.kind == kind &&
      other.host == host &&
      other.port == port &&
      other.path == path;

  @override
  int get hashCode => Object.hash(kind, host, port, path);
}

const Map<String, SourceKind> _dnsSdTypes = {
  '_smb._tcp': SourceKind.smb,
  '_nfs._tcp': SourceKind.nfs,
  '_webdav._tcp': SourceKind.webdav,
  '_webdavs._tcp': SourceKind.webdav,
  '_ftp._tcp': SourceKind.ftp,
  '_sftp-ssh._tcp': SourceKind.sftp,
};

/// mDNS/DNS-SD, WS-Discovery (Windows hosts sharing over SMB) and NetBIOS
/// name queries merged and de-duplicated (NET-001 discovery; NET-002/003/
/// 004 via DNS-SD types).
Stream<DiscoveredShare> discoverShares({
  Duration timeout = const Duration(seconds: 3),
}) {
  final out = StreamController<DiscoveredShare>();
  final seen = <DiscoveredShare>{};
  void add(DiscoveredShare s) {
    if (seen.add(s)) out.add(s);
  }

  var pending = 3;
  void done() {
    if (--pending == 0) unawaited(out.close());
  }

  browseDnsSd(_dnsSdTypes.keys.toList(), timeout: timeout).listen(
    (s) => add(
      DiscoveredShare(
        kind: _dnsSdTypes[s.type]!,
        name: s.instance,
        host: s.connectHost,
        port: _defaultPort(_dnsSdTypes[s.type]!, s.port, s.type),
        path: s.txt['path'],
        via: 'mdns',
      ),
    ),
    onError: (Object _) {},
    onDone: done,
  );
  wsDiscovery(timeout: timeout).listen(
    (h) => add(
      DiscoveredShare(
        kind: SourceKind.smb,
        name: h.$2 ?? h.$1,
        host: h.$1,
        via: 'wsd',
      ),
    ),
    onError: (Object _) {},
    onDone: done,
  );
  netbiosNames(timeout: timeout).listen(
    (h) => add(
      DiscoveredShare(
        kind: SourceKind.smb,
        name: h.$2,
        host: h.$1,
        via: 'netbios',
      ),
    ),
    onError: (Object _) {},
    onDone: done,
  );
  return out.stream;
}

int? _defaultPort(SourceKind k, int port, String type) => switch ((k, port)) {
  (SourceKind.smb, 445) ||
  (SourceKind.nfs, 2049) ||
  (SourceKind.ftp, 21) ||
  (SourceKind.sftp, 22) => null,
  (SourceKind.webdav, 80) when type == '_webdav._tcp' => null,
  _ => port,
};

/// WS-Discovery probe (UDP 3702): Windows 10/11 and many NASes answer with
/// their XAddrs; yields `(ip, computer name?)`.
Stream<(String, String?)> wsDiscovery({
  Duration timeout = const Duration(seconds: 3),
  InternetAddress? target,
  int port = 3702,
}) async* {
  final to = target ?? InternetAddress('239.255.255.250');
  final socket = await RawDatagramSocket.bind(
    to.isLoopback ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
    0,
  );
  final id =
      'urn:uuid:${List.generate(4, (_) => Random.secure().nextInt(1 << 32).toRadixString(16)).join('-')}';
  final probe =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" '
      'xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing" '
      'xmlns:wsd="http://schemas.xmlsoap.org/ws/2005/04/discovery" '
      'xmlns:wsdp="http://schemas.xmlsoap.org/ws/2006/02/devprof">'
      '<soap:Header><wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>'
      '<wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>'
      '<wsa:MessageID>$id</wsa:MessageID></soap:Header>'
      '<soap:Body><wsd:Probe><wsd:Types>wsdp:Device</wsd:Types></wsd:Probe></soap:Body></soap:Envelope>';
  final out = StreamController<(String, String?)>();
  final seen = <String>{};
  final sub = socket.listen((e) {
    if (e != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null || d.data.length > 65000) return;
    try {
      final doc = parseXml(
        utf8.decode(d.data, allowMalformed: true),
        limits: const XmlLimits(maxLength: 65536, maxNodes: 2000),
      );
      for (final x in doc.descendants('XAddrs')) {
        for (final addr in x.text.split(RegExp(r'\s+'))) {
          final u = Uri.tryParse(addr);
          if (u == null || u.host.isEmpty) continue;
          final ip = InternetAddress.tryParse(
            u.host.replaceAll(RegExp(r'[\[\]]'), ''),
          );
          if (ip == null || ip.type != InternetAddressType.IPv4) continue;
          if (seen.add(ip.address)) out.add((ip.address, null));
        }
      }
    } on FormatException {
      // Not ours.
    }
  });
  socket.send(utf8.encode(probe), to, port);
  final timer = Timer(timeout, () => unawaited(out.close()));
  try {
    yield* out.stream;
  } finally {
    timer.cancel();
    await sub.cancel();
    socket.close();
  }
}

/// NetBIOS node-status broadcast (UDP 137): legacy SMB hosts that announce
/// no mDNS or WSD; yields `(ip, NetBIOS name)` for file servers (<20>).
Stream<(String, String)> netbiosNames({
  Duration timeout = const Duration(seconds: 3),
  InternetAddress? target,
  int port = 137,
}) async* {
  final to = target ?? InternetAddress('255.255.255.255');
  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(
      to.isLoopback ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
      0,
    );
  } on SocketException {
    return;
  }
  socket.broadcastEnabled = true;
  final out = StreamController<(String, String)>();
  final sub = socket.listen((e) {
    if (e != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    final name = parseNodeStatus(d.data);
    if (name != null) out.add((d.address.address, name));
  });
  try {
    socket.send(nodeStatusQuery(Random().nextInt(1 << 16)), to, port);
  } on SocketException {
    // Broadcast not permitted on this network.
  }
  final timer = Timer(timeout, () => unawaited(out.close()));
  try {
    yield* out.stream;
  } finally {
    timer.cancel();
    await sub.cancel();
    socket.close();
  }
}

/// NBSTAT query for the wildcard name `*` (RFC 1002 §4.2.17).
Uint8List nodeStatusQuery(int id) {
  final b = BytesBuilder()
    ..add([id >> 8, id & 0xff, 0x00, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
    ..addByte(32);
  // "*" padded with NULs, first-level encoded: each nibble + 'A'.
  final raw = [0x2A, ...List.filled(15, 0)];
  for (final c in raw) {
    b
      ..addByte(0x41 + (c >> 4))
      ..addByte(0x41 + (c & 0x0F));
  }
  b
    ..addByte(0)
    ..add([0x00, 0x21, 0x00, 0x01]); // NBSTAT, IN
  return b.takeBytes();
}

/// The file-server name (suffix 0x20, unique) of a node-status response.
String? parseNodeStatus(Uint8List m) {
  if (m.length < 57) return null;
  // Header 12 + encoded name 34 + type/class/ttl/rdlength 10.
  var p = 12 + 34 + 10;
  final count = m[p];
  p++;
  for (var i = 0; i < count && p + 18 <= m.length; i++) {
    final name = latin1.decode(m.sublist(p, p + 15)).trimRight();
    final suffix = m[p + 15];
    final flags = (m[p + 16] << 8) | m[p + 17];
    final group = flags & 0x8000 != 0;
    if (suffix == 0x20 && !group && name.isNotEmpty) return name;
    p += 18;
  }
  return null;
}
