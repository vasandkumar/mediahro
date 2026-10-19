import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// SSDP multicast group (UPnP 1.1 §1).
final InternetAddress ssdpGroup = InternetAddress('239.255.255.250');
const int ssdpPort = 1900;

/// One SSDP search response or NOTIFY.
@immutable
final class SsdpMessage {
  const SsdpMessage({
    required this.headers,
    required this.from,
    this.startLine = '',
  });

  final String startLine;

  /// Upper-case header names.
  final Map<String, String> headers;
  final InternetAddress from;

  String? get location => headers['LOCATION'];
  String? get st => headers['ST'] ?? headers['NT'];
  String? get usn => headers['USN'];
  String? get nts => headers['NTS'];
  bool get isSearch => startLine.startsWith('M-SEARCH');
  bool get isNotify => startLine.startsWith('NOTIFY');
}

/// Parses an SSDP datagram (HTTP-over-UDP). Returns null for garbage.
SsdpMessage? parseSsdp(List<int> datagram, InternetAddress from) {
  if (datagram.length > 8192) return null;
  final text = latin1.decode(datagram, allowInvalid: true);
  final lines = text.split(RegExp('\r?\n'));
  if (lines.isEmpty) return null;
  final start = lines.first.trim();
  if (!start.startsWith('HTTP/1.') &&
      !start.startsWith('NOTIFY') &&
      !start.startsWith('M-SEARCH')) {
    return null;
  }
  final headers = <String, String>{};
  for (final l in lines.skip(1)) {
    final i = l.indexOf(':');
    if (i <= 0) continue;
    headers[l.substring(0, i).trim().toUpperCase()] = l.substring(i + 1).trim();
  }
  return SsdpMessage(headers: headers, from: from, startLine: start);
}

/// Builds an `M-SEARCH` request for [searchTarget].
List<int> ssdpSearch(String searchTarget, {int mx = 2}) => latin1.encode(
  'M-SEARCH * HTTP/1.1\r\n'
  'HOST: 239.255.255.250:1900\r\n'
  'MAN: "ssdp:discover"\r\n'
  'MX: $mx\r\n'
  'ST: $searchTarget\r\n'
  'USER-AGENT: Mediahro/1.0 UPnP/1.1\r\n\r\n',
);

/// Sends M-SEARCH for [searchTarget] and collects distinct responses
/// (by USN) for [timeout]. Requires the multicast entitlement on Apple
/// platforms (docs/07) and CHANGE_WIFI_MULTICAST_STATE on Android.
Stream<SsdpMessage> ssdpDiscover(
  String searchTarget, {
  Duration timeout = const Duration(seconds: 3),
  int repeats = 2,
  InternetAddress? target,
  int port = ssdpPort,
}) async* {
  final to = target ?? ssdpGroup;
  final socket = await RawDatagramSocket.bind(
    to.isLoopback ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
    0,
  );
  final seen = <String>{};
  final out = StreamController<SsdpMessage>();
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    final m = parseSsdp(d.data, d.address);
    if (m == null || m.location == null) return;
    final key = m.usn ?? '${m.location}';
    if (seen.add(key)) out.add(m);
  });
  final payload = ssdpSearch(searchTarget, mx: timeout.inSeconds.clamp(1, 5));
  for (var i = 0; i < repeats; i++) {
    socket.send(payload, to, port);
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
