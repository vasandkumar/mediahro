import 'dart:convert';

import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:meta/meta.dart';

@immutable
final class UpnpService {
  const UpnpService({
    required this.serviceType,
    required this.controlUrl,
    this.eventSubUrl,
    this.scpdUrl,
  });

  final String serviceType;
  final Uri controlUrl;
  final Uri? eventSubUrl;
  final Uri? scpdUrl;
}

/// A UPnP device from its description document (UDA 1.1 §2).
@immutable
final class UpnpDevice {
  const UpnpDevice({
    required this.udn,
    required this.deviceType,
    required this.friendlyName,
    required this.location,
    this.manufacturer,
    this.modelName,
    this.iconUrl,
    this.services = const [],
  });

  final String udn;
  final String deviceType;
  final String friendlyName;
  final Uri location;
  final String? manufacturer;
  final String? modelName;
  final Uri? iconUrl;
  final List<UpnpService> services;

  UpnpService? service(String typePrefix) {
    for (final s in services) {
      if (s.serviceType.startsWith(typePrefix)) return s;
    }
    return null;
  }

  static const contentDirectory =
      'urn:schemas-upnp-org:service:ContentDirectory:';
  static const mediaServer = 'urn:schemas-upnp-org:device:MediaServer:';

  bool get isMediaServer => service(contentDirectory) != null;
}

/// Parses a device description; embedded devices are searched for the
/// first one with a ContentDirectory (or the root when none has one).
UpnpDevice parseDeviceDescription(String xml, Uri location) {
  final root = parseXml(
    xml,
    limits: const XmlLimits(maxLength: 1 << 20, maxNodes: 20000),
  );
  final urlBase = Uri.tryParse(root.childText('URLBase') ?? '');
  final base = urlBase != null && urlBase.hasScheme ? urlBase : location;
  final top = root.child('device');
  if (top == null) throw const FormatException('no <device> in description');
  var pick = top;
  for (final d in [top, ...top.descendants('device')]) {
    final list = d.child('serviceList');
    if (list != null &&
        list
            .all('service')
            .any(
              (s) => (s.childText('serviceType') ?? '').startsWith(
                UpnpDevice.contentDirectory,
              ),
            )) {
      pick = d;
      break;
    }
  }
  Uri? abs(String? u) => u == null || u.isEmpty ? null : base.resolve(u);
  Uri? icon;
  var best = 0;
  for (final i in pick.child('iconList')?.all('icon') ?? const <XmlElement>[]) {
    final w = int.tryParse(i.childText('width') ?? '') ?? 0;
    final mime = i.childText('mimetype') ?? '';
    if (w > best && (mime.contains('png') || mime.contains('jpeg'))) {
      best = w;
      icon = abs(i.childText('url'));
    }
  }
  return UpnpDevice(
    udn: pick.childText('UDN') ?? location.toString(),
    deviceType: pick.childText('deviceType') ?? '',
    friendlyName: pick.childText('friendlyName') ?? location.host,
    location: location,
    manufacturer: pick.childText('manufacturer'),
    modelName: pick.childText('modelName'),
    iconUrl: icon,
    services: [
      for (final s
          in pick.child('serviceList')?.all('service') ?? const <XmlElement>[])
        if (abs(s.childText('controlURL')) case final Uri control)
          UpnpService(
            serviceType: s.childText('serviceType') ?? '',
            controlUrl: control,
            eventSubUrl: abs(s.childText('eventSubURL')),
            scpdUrl: abs(s.childText('SCPDURL')),
          ),
    ],
  );
}

final class UpnpError implements Exception {
  const UpnpError(this.code, this.description);

  final int code;
  final String description;

  @override
  String toString() => 'UpnpError($code: $description)';
}

/// SOAP action call (UDA 1.1 §3.2). Arguments are escaped; the response
/// arguments come back as a map of local names to text.
Future<Map<String, String>> soapCall(
  HttpSession session,
  UpnpService service,
  String action,
  Map<String, String> args,
) async {
  final body = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>')
    ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ')
    ..write(
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>',
    )
    ..write('<u:$action xmlns:u="${xmlEscape(service.serviceType)}">');
  args.forEach((k, v) => body.write('<$k>${xmlEscape(v)}</$k>'));
  body.write('</u:$action></s:Body></s:Envelope>');
  final (status, _, bytes) = await session.fetch(
    'POST',
    service.controlUrl,
    extra: {
      'Content-Type': 'text/xml; charset="utf-8"',
      'SOAPACTION': '"${service.serviceType}#$action"',
    },
    body: utf8.encode(body.toString()),
  );
  final text = utf8.decode(bytes, allowMalformed: true);
  final XmlElement env;
  try {
    env = parseXml(
      text,
      limits: const XmlLimits(maxLength: 16 << 20, maxNodes: 500000),
    );
  } on XmlFormatException {
    throw UpnpError(status, 'malformed SOAP response (HTTP $status)');
  }
  final b = env.child('Body');
  if (status != 200) {
    final err = b?.descendants('UPnPError').firstOrNull;
    throw UpnpError(
      int.tryParse(err?.childText('errorCode') ?? '') ?? status,
      err?.childText('errorDescription') ?? 'HTTP $status',
    );
  }
  final resp = b?.children.firstOrNull;
  return {
    for (final c in resp?.children ?? const <XmlElement>[]) c.localName: c.text,
  };
}

/// Fetches and parses the description at [location] (LAN host; allowed by
/// the LAN-discovery policy).
Future<UpnpDevice> fetchDevice(HttpSession session, Uri location) async {
  final (status, _, body) = await session.fetch(
    'GET',
    location,
    maxBytes: 1 << 20,
  );
  HttpSession.check(status, location);
  return parseDeviceDescription(
    utf8.decode(body, allowMalformed: true),
    location,
  );
}
