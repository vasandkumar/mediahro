import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One DNS-SD service instance (RFC 6763).
@immutable
final class DnsSdService {
  const DnsSdService({
    required this.type,
    required this.instance,
    required this.host,
    required this.port,
    this.addresses = const [],
    this.txt = const {},
  });

  /// `_smb._tcp`, `_webdav._tcp`, ...
  final String type;

  /// Human-readable instance name (`Living Room NAS`).
  final String instance;

  /// Target host name (`nas.local`).
  final String host;
  final int port;
  final List<InternetAddress> addresses;
  final Map<String, String> txt;

  /// Best address to connect to (IPv4 first; falls back to the name).
  String get connectHost =>
      addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull
          ?.address ??
      host;
}

final InternetAddress mdnsGroup = InternetAddress('224.0.0.251');
const int mdnsPort = 5353;

const int _typeA = 1;
const int _typePtr = 12;
const int _typeTxt = 16;
const int _typeAaaa = 28;
const int _typeSrv = 33;

/// Encodes a one-question query for [name] of [qtype], unicast-response
/// requested (QU bit) so answers come back to our ephemeral port.
Uint8List encodeMdnsQuery(String name, {int qtype = _typePtr}) {
  final b = BytesBuilder()
    ..add([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]); // id 0, flags 0, qd=1
  for (final label in name.split('.').where((l) => l.isNotEmpty)) {
    final bytes = utf8.encode(label);
    b
      ..addByte(bytes.length)
      ..add(bytes);
  }
  b
    ..addByte(0)
    ..add([qtype >> 8, qtype & 0xff, 0x80, 0x01]); // class IN | QU
  return b.takeBytes();
}

/// A decoded resource record.
@immutable
final class DnsRecord {
  const DnsRecord(this.name, this.type, this.data, this.message, this.offset);

  final String name;
  final int type;
  final Uint8List data;

  /// Whole message and rdata offset, for compressed names inside rdata.
  final Uint8List message;
  final int offset;
}

final class DnsFormatException extends FormatException {
  const DnsFormatException(super.message);
}

/// Decodes the answer, authority and additional sections of a DNS message.
List<DnsRecord> decodeDnsRecords(Uint8List m) {
  if (m.length < 12 || m.length > 9000) {
    throw const DnsFormatException('bad size');
  }
  final bd = ByteData.sublistView(m);
  final qd = bd.getUint16(4);
  final rrCount = bd.getUint16(6) + bd.getUint16(8) + bd.getUint16(10);
  var p = 12;
  for (var i = 0; i < qd; i++) {
    p = readDnsName(m, p).$2 + 4;
  }
  final out = <DnsRecord>[];
  for (var i = 0; i < rrCount && p < m.length; i++) {
    final (name, next) = readDnsName(m, p);
    if (next + 10 > m.length) {
      throw const DnsFormatException('truncated record');
    }
    final type = bd.getUint16(next);
    final len = bd.getUint16(next + 8);
    final start = next + 10;
    if (start + len > m.length) {
      throw const DnsFormatException('truncated rdata');
    }
    out.add(
      DnsRecord(
        name,
        type,
        Uint8List.sublistView(m, start, start + len),
        m,
        start,
      ),
    );
    p = start + len;
  }
  return out;
}

/// Reads a (possibly compressed) name at [offset]; returns it and the
/// offset after it. Pointer loops and over-long names are rejected.
(String, int) readDnsName(Uint8List m, int offset) {
  final labels = <String>[];
  var p = offset;
  int? end;
  var jumps = 0;
  while (true) {
    if (p >= m.length) throw const DnsFormatException('name past end');
    final len = m[p];
    if (len == 0) {
      end ??= p + 1;
      break;
    }
    if (len & 0xC0 == 0xC0) {
      if (p + 1 >= m.length || ++jumps > 16) {
        throw const DnsFormatException('bad pointer');
      }
      end ??= p + 2;
      p = ((len & 0x3F) << 8) | m[p + 1];
      continue;
    }
    if (p + 1 + len > m.length) {
      throw const DnsFormatException('label past end');
    }
    labels.add(
      utf8.decode(m.sublist(p + 1, p + 1 + len), allowMalformed: true),
    );
    if (labels.length > 64) throw const DnsFormatException('name too long');
    p += 1 + len;
  }
  return (labels.join('.'), end);
}

/// Browses DNS-SD [types] (e.g. `_smb._tcp`) on the LAN for [timeout].
/// Needs the multicast entitlement on Apple platforms and
/// CHANGE_WIFI_MULTICAST_STATE on Android (docs/07); lane C4 holds the
/// multicast lock while this runs.
Stream<DnsSdService> browseDnsSd(
  List<String> types, {
  Duration timeout = const Duration(seconds: 3),
  InternetAddress? target,
  int port = mdnsPort,
}) async* {
  final to = target ?? mdnsGroup;
  final socket = await RawDatagramSocket.bind(
    to.isLoopback ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
    0,
  );
  final out = StreamController<DnsSdService>();
  final ptrs = <String, String>{}; // instance fqdn → type
  final srv = <String, (String, int)>{};
  final txt = <String, Map<String, String>>{};
  final addrs = <String, List<InternetAddress>>{};
  final emitted = <String>{};

  void tryEmit() {
    for (final MapEntry(key: inst, value: type) in ptrs.entries) {
      if (emitted.contains(inst)) continue;
      final s = srv[inst];
      if (s == null) continue;
      final a = addrs[s.$1] ?? const <InternetAddress>[];
      emitted.add(inst);
      final suffix = '.$type.local';
      out.add(
        DnsSdService(
          type: type,
          instance: inst.endsWith(suffix)
              ? inst.substring(0, inst.length - suffix.length)
              : inst,
          host: s.$1,
          port: s.$2,
          addresses: a,
          txt: txt[inst] ?? const {},
        ),
      );
    }
  }

  final sub = socket.listen((e) {
    if (e != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    try {
      for (final r in decodeDnsRecords(d.data)) {
        switch (r.type) {
          case _typePtr:
            final type = types
                .where((t) => r.name.toLowerCase() == '$t.local'.toLowerCase())
                .firstOrNull;
            if (type != null) ptrs[readDnsName(r.message, r.offset).$1] = type;
          case _typeSrv when r.data.length >= 7:
            final port = (r.data[4] << 8) | r.data[5];
            srv[r.name] = (readDnsName(r.message, r.offset + 6).$1, port);
          case _typeTxt:
            txt[r.name] = _decodeTxt(r.data);
          case _typeA when r.data.length == 4:
            (addrs[r.name] ??= []).add(InternetAddress.fromRawAddress(r.data));
          case _typeAaaa when r.data.length == 16:
            (addrs[r.name] ??= []).add(InternetAddress.fromRawAddress(r.data));
        }
      }
      tryEmit();
    } on DnsFormatException {
      // Ignore malformed packets from the LAN.
    }
  });
  for (final t in types) {
    socket.send(encodeMdnsQuery('$t.local'), to, port);
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

Map<String, String> _decodeTxt(Uint8List d) {
  final out = <String, String>{};
  var p = 0;
  while (p < d.length) {
    final len = d[p];
    if (p + 1 + len > d.length) break;
    final s = utf8.decode(d.sublist(p + 1, p + 1 + len), allowMalformed: true);
    final eq = s.indexOf('=');
    if (eq > 0) {
      out[s.substring(0, eq)] = s.substring(eq + 1);
    } else if (s.isNotEmpty) {
      out[s] = '';
    }
    p += 1 + len;
  }
  return out;
}
