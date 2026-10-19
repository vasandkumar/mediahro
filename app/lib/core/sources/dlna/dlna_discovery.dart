import 'dart:async';
import 'dart:io';

import 'package:mediahro/core/sources/discovery/ssdp.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Finds DLNA/UPnP media servers on the LAN (NET-005): SSDP search, then
/// each device description. Devices that fail to describe are skipped.
Stream<UpnpDevice> discoverMediaServers(
  HttpSession session, {
  Duration timeout = const Duration(seconds: 3),
  InternetAddress? target,
  int port = ssdpPort,
}) async* {
  final seen = <String>{};
  await for (final m in ssdpDiscover(
    'urn:schemas-upnp-org:device:MediaServer:1',
    timeout: timeout,
    target: target,
    port: port,
  )) {
    final loc = Uri.tryParse(m.location ?? '');
    if (loc == null || !seen.add(loc.toString())) continue;
    try {
      final d = await fetchDevice(session, loc);
      if (d.isMediaServer) yield d;
    } on VirtualFileException {
      continue;
    } on FormatException {
      continue;
    }
  }
}
