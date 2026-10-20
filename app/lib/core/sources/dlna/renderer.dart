// XML and SOAP templates are concatenated without separators on purpose.
// ignore_for_file: missing_whitespace_between_adjacent_strings
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/parsers/xml_lite.dart';
import 'package:mediahro/core/sources/discovery/ssdp.dart';
import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// UPnP AVTransport states.
enum TransportState {
  stopped('STOPPED'),
  playing('PLAYING'),
  paused('PAUSED_PLAYBACK'),
  transitioning('TRANSITIONING'),
  noMedia('NO_MEDIA_PRESENT');

  const TransportState(this.wire);

  final String wire;
}

@immutable
final class RendererStatus {
  const RendererStatus({
    this.state = TransportState.noMedia,
    this.uri,
    this.metadata = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 50,
    this.muted = false,
  });

  final TransportState state;
  final Uri? uri;

  /// DIDL-Lite metadata sent by the control point (title, art).
  final String metadata;
  final Duration position;
  final Duration duration;
  final int volume;
  final bool muted;

  RendererStatus copyWith({
    TransportState? state,
    Uri? uri,
    String? metadata,
    Duration? position,
    Duration? duration,
    int? volume,
    bool? muted,
  }) => RendererStatus(
    state: state ?? this.state,
    uri: uri ?? this.uri,
    metadata: metadata ?? this.metadata,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
  );
}

/// Where pushed media plays: the app wires this to the playback engine
/// (lane C1/B1). Implementations report state changes on [changes].
abstract interface class RendererSink {
  RendererStatus get status;
  Stream<RendererStatus> get changes;
  Future<void> load(Uri uri, {required String metadata});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(int volume);
  Future<void> setMute({required bool muted});
}

const _avt = 'urn:schemas-upnp-org:service:AVTransport:1';
const _rc = 'urn:schemas-upnp-org:service:RenderingControl:1';
const _cm = 'urn:schemas-upnp-org:service:ConnectionManager:1';
const _deviceType = 'urn:schemas-upnp-org:device:MediaRenderer:1';

/// Mediahro as a DLNA/UPnP MediaRenderer (NET-005 "our own renderer
/// exposure (opt-in)"): TVs and phones on the LAN can push media to it.
/// Off until the user enables it; stops when the app leaves the
/// foreground on mobile (lane C4 drives [start]/[stop]).
final class DlnaRenderer {
  DlnaRenderer({
    required this.friendlyName,
    required this.uuid,
    required this.sink,
    required this.gateway,
    this.allowHost,
    this.ssdpListenPort = ssdpPort,
    this.advertiseAddress,
  });

  final String friendlyName;
  final String uuid;
  final RendererSink sink;

  /// For GENA NOTIFY callbacks to control points (LAN hosts only).
  final NetworkGateway gateway;

  /// Lets the engine fetch the pushed media's host (session allow).
  final void Function(String host)? allowHost;
  final int ssdpListenPort;

  /// Address put in LOCATION; defaults to the first LAN IPv4.
  final InternetAddress? advertiseAddress;

  HttpServer? _http;
  RawDatagramSocket? _ssdp;
  Timer? _alive;
  StreamSubscription<RendererStatus>? _statusSub;
  final _subs = <String, _Subscription>{};
  final _random = Random.secure();
  InternetAddress? _address;

  bool get isRunning => _http != null;

  /// The bound SSDP port (tests bind an ephemeral one).
  int get boundSsdpPort => _ssdp!.port;
  Uri get location =>
      Uri.parse('http://${_address!.address}:${_http!.port}/description.xml');

  static const List<String> searchTargets = [
    'upnp:rootdevice',
    _deviceType,
    _avt,
    _rc,
    _cm,
  ];

  Future<void> start({int httpPort = 0}) async {
    if (isRunning) return;
    _address = advertiseAddress ?? await _lanAddress();
    _http = await HttpServer.bind(_address, httpPort)
      ..listen(_handle);
    final udp = await RawDatagramSocket.bind(
      _address!.isLoopback
          ? InternetAddress.loopbackIPv4
          : InternetAddress.anyIPv4,
      ssdpListenPort,
      reusePort: !Platform.isWindows && !Platform.isAndroid,
    );
    if (!_address!.isLoopback) {
      try {
        udp.joinMulticast(ssdpGroup);
      } on SocketException {
        // Multicast unavailable (entitlement or network); unicast still works.
      }
    }
    _ssdp = udp;
    udp.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = udp.receive();
      if (d == null) return;
      final m = parseSsdp(d.data, d.address);
      if (m == null || !m.isSearch) return;
      final st = m.headers['ST'] ?? '';
      final targets = st == 'ssdp:all'
          ? searchTargets
          : [if (searchTargets.contains(st) || st == 'uuid:$uuid') st];
      for (final t in targets) {
        udp.send(_searchResponse(t), d.address, d.port);
      }
    });
    _notify('ssdp:alive');
    _alive = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _notify('ssdp:alive'),
    );
    _statusSub = sink.changes.listen((_) => unawaited(_emitEvents()));
  }

  Future<void> stop() async {
    if (!isRunning) return;
    _notify('ssdp:byebye');
    _alive?.cancel();
    await _statusSub?.cancel();
    _ssdp?.close();
    _ssdp = null;
    await _http?.close(force: true);
    _http = null;
    _subs.clear();
  }

  List<int> _searchResponse(String st) => latin1.encode(
    'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\n'
    'LOCATION: $location\r\nSERVER: ${Platform.operatingSystem}/1.0 UPnP/1.0 Mediahro/1.0\r\n'
    'ST: $st\r\nUSN: uuid:$uuid${st == 'uuid:$uuid' ? '' : '::$st'}\r\n\r\n',
  );

  void _notify(String nts) {
    final udp = _ssdp;
    if (udp == null || _address!.isLoopback) return;
    for (final t in ['uuid:$uuid', ...searchTargets]) {
      final msg = latin1.encode(
        'NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\n'
        'LOCATION: $location\r\nNT: $t\r\nNTS: $nts\r\nSERVER: Mediahro/1.0 UPnP/1.0\r\n'
        'USN: uuid:$uuid${t.startsWith('uuid:') ? '' : '::$t'}\r\n\r\n',
      );
      udp.send(msg, ssdpGroup, ssdpPort);
    }
  }

  Future<void> _handle(HttpRequest r) async {
    final res = r.response;
    try {
      switch ((r.method, r.uri.path)) {
        case ('GET', '/description.xml'):
          _xml(res, _description());
        case ('GET', '/avt.xml') || ('GET', '/rc.xml') || ('GET', '/cm.xml'):
          _xml(res, _scpd(r.uri.path));
        case ('POST', final String p) when p.endsWith('/control'):
          await _control(r, p.split('/')[1]);
        case ('SUBSCRIBE', final String p) when p.endsWith('/event'):
          _subscribe(r, p.split('/')[1]);
        case ('UNSUBSCRIBE', _):
          _subs.remove(r.headers.value('sid'));
        default:
          res.statusCode = 404;
      }
    } on FormatException {
      // 714: illegal MIME type / unsupported resource (AVTransport:1).
      _fault(res, 714, 'Illegal MIME-type');
    } on Object {
      _fault(res, 501, 'Action Failed');
    }
    await res.close();
  }

  void _xml(HttpResponse res, String body) {
    res.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    res.write(body);
  }

  Future<void> _control(HttpRequest r, String service) async {
    final body = await utf8.decodeStream(r.take(1 << 20));
    final env = parseXml(
      body,
      limits: const XmlLimits(maxLength: 1 << 20, maxNodes: 2000),
    );
    final action = env.child('Body')?.children.firstOrNull;
    if (action == null) {
      _fault(r.response, 401, 'Invalid Action');
      return;
    }
    final args = {for (final c in action.children) c.localName: c.text};
    final type = switch (service) {
      'avt' => _avt,
      'rc' => _rc,
      _ => _cm,
    };
    final out = await _invoke(service, action.localName, args);
    if (out == null) {
      _fault(r.response, 401, 'Invalid Action');
      return;
    }
    final b = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
      '<u:${action.localName}Response xmlns:u="$type">',
    );
    out.forEach((k, v) => b.write('<$k>${xmlEscape(v)}</$k>'));
    b.write('</u:${action.localName}Response></s:Body></s:Envelope>');
    _xml(r.response, b.toString());
  }

  /// Runs one action; null when unknown. Errors become UPnP faults.
  Future<Map<String, String>?> _invoke(
    String service,
    String action,
    Map<String, String> a,
  ) async {
    final s = sink.status;
    switch ((service, action)) {
      case ('avt', 'SetAVTransportURI'):
        final uri = Uri.tryParse(a['CurrentURI'] ?? '');
        if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
          throw const FormatException('unsupported URI');
        }
        allowHost?.call(uri.host);
        await sink.load(uri, metadata: a['CurrentURIMetaData'] ?? '');
        return {};
      case ('avt', 'Play'):
        await sink.play();
        return {};
      case ('avt', 'Pause'):
        await sink.pause();
        return {};
      case ('avt', 'Stop'):
        await sink.stop();
        return {};
      case ('avt', 'Seek'):
        final t = _parseTime(a['Target'] ?? '');
        if (t != null) await sink.seek(t);
        return {};
      case ('avt', 'GetTransportInfo'):
        return {
          'CurrentTransportState': s.state.wire,
          'CurrentTransportStatus': 'OK',
          'CurrentSpeed': '1',
        };
      case ('avt', 'GetPositionInfo'):
        return {
          'Track': s.uri == null ? '0' : '1',
          'TrackDuration': formatUpnpTime(s.duration),
          'TrackMetaData': s.metadata,
          'TrackURI': '${s.uri ?? ''}',
          'RelTime': formatUpnpTime(s.position),
          'AbsTime': formatUpnpTime(s.position),
          'RelCount': '2147483647',
          'AbsCount': '2147483647',
        };
      case ('avt', 'GetMediaInfo'):
        return {
          'NrTracks': s.uri == null ? '0' : '1',
          'MediaDuration': formatUpnpTime(s.duration),
          'CurrentURI': '${s.uri ?? ''}',
          'CurrentURIMetaData': s.metadata,
          'NextURI': '',
          'NextURIMetaData': '',
          'PlayMedium': 'NETWORK',
          'RecordMedium': 'NOT_IMPLEMENTED',
          'WriteStatus': 'NOT_IMPLEMENTED',
        };
      case ('avt', 'GetTransportSettings'):
        return {'PlayMode': 'NORMAL', 'RecQualityMode': 'NOT_IMPLEMENTED'};
      case ('avt', 'GetCurrentTransportActions'):
        return {'Actions': 'Play,Pause,Stop,Seek'};
      case ('rc', 'GetVolume'):
        return {'CurrentVolume': '${s.volume}'};
      case ('rc', 'SetVolume'):
        await sink.setVolume(
          (int.tryParse(a['DesiredVolume'] ?? '') ?? s.volume).clamp(0, 100),
        );
        return {};
      case ('rc', 'GetMute'):
        return {'CurrentMute': s.muted ? '1' : '0'};
      case ('rc', 'SetMute'):
        await sink.setMute(
          muted: a['DesiredMute'] == '1' || a['DesiredMute'] == 'true',
        );
        return {};
      case ('cm', 'GetProtocolInfo'):
        return {'Source': '', 'Sink': protocolInfoSink};
      case ('cm', 'GetCurrentConnectionIDs'):
        return {'ConnectionIDs': '0'};
      case ('cm', 'GetCurrentConnectionInfo'):
        return {
          'RcsID': '0',
          'AVTransportID': '0',
          'ProtocolInfo': '',
          'PeerConnectionManager': '',
          'PeerConnectionID': '-1',
          'Direction': 'Input',
          'Status': 'OK',
        };
    }
    return null;
  }

  void _fault(HttpResponse res, int code, String text) {
    res.statusCode = 500;
    _xml(
      res,
      '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
      '<faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>'
      '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>$code</errorCode>'
      '<errorDescription>$text</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>',
    );
  }

  void _subscribe(HttpRequest r, String service) {
    final cb = RegExp('<([^>]+)>')
        .firstMatch(r.headers.value('callback') ?? '')
        ?.group(1);
    final existing = r.headers.value('sid');
    final res = r.response;
    if (existing != null && _subs.containsKey(existing)) {
      _subs[existing]!.expires = DateTime.now().add(
        const Duration(seconds: 1800),
      );
      res.headers.set('SID', existing);
    } else {
      final uri = cb == null ? null : Uri.tryParse(cb);
      if (uri == null || !isLocalNetworkHost(uri.host)) {
        res.statusCode = 412;
        return;
      }
      final sid =
          'uuid:${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      _subs[sid] = _Subscription(
        uri,
        service,
        DateTime.now().add(const Duration(seconds: 1800)),
      );
      res.headers.set('SID', sid);
      // The initial event (SEQ 0) goes first on this subscription's chain.
      Timer.run(() => unawaited(_send(sid)));
    }
    res.headers.set('TIMEOUT', 'Second-1800');
  }

  Future<void> _emitEvents() async {
    for (final sid in _subs.keys.toList()) {
      await _send(sid);
    }
  }

  /// UPnP GENA: each subscription's events are numbered from 0 and
  /// delivered one at a time, in order.
  Future<void> _send(String sid) {
    final sub = _subs[sid];
    if (sub == null) return Future.value();
    final next = sub.tail.then((_) => _deliver(sid, sub));
    sub.tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _deliver(String sid, _Subscription sub) async {
    if (!identical(_subs[sid], sub)) return;
    final uri = sub.callback;
    final service = sub.service;
    if (DateTime.now().isAfter(sub.expires)) {
      _subs.remove(sid);
      return;
    }
    final s = sink.status;
    final instance = service == 'rc'
        ? '<Volume channel="Master" val="${s.volume}"/><Mute channel="Master" val="${s.muted ? 1 : 0}"/>'
        : '<TransportState val="${s.state.wire}"/><CurrentTrackURI val="${xmlEscape('${s.uri ?? ''}')}"/>'
              '<CurrentTrackDuration val="${formatUpnpTime(s.duration)}"/>';
    final ns = service == 'rc'
        ? 'urn:schemas-upnp-org:metadata-1-0/RCS/'
        : 'urn:schemas-upnp-org:metadata-1-0/AVT/';
    final lastChange =
        '<Event xmlns="$ns"><InstanceID val="0">$instance</InstanceID></Event>';
    final body =
        '<?xml version="1.0"?><e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">'
        '<e:property><LastChange>${xmlEscape(lastChange)}</LastChange></e:property></e:propertyset>';
    try {
      final res = await gateway.send(
        HttpRequestData(
          method: 'NOTIFY',
          uri: uri,
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'NT': 'upnp:event',
            'NTS': 'upnp:propchange',
            'SID': sid,
            'SEQ': '${sub.seq++}',
          },
          body: utf8.encode(body),
        ),
      );
      if (res.statusCode == 412) _subs.remove(sid);
    } on Object {
      _subs.remove(sid);
    }
  }

  String _description() =>
      '<?xml version="1.0" encoding="utf-8"?>'
      '<root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:dlna="urn:schemas-dlna-org:device-1-0">'
      '<specVersion><major>1</major><minor>0</minor></specVersion><device>'
      '<deviceType>$_deviceType</deviceType><friendlyName>${xmlEscape(friendlyName)}</friendlyName>'
      '<manufacturer>Mediahro</manufacturer><modelName>Mediahro</modelName>'
      '<UDN>uuid:$uuid</UDN><dlna:X_DLNADOC>DMR-1.50</dlna:X_DLNADOC><serviceList>'
      '${_service(_avt, 'AVTransport', 'avt')}${_service(_rc, 'RenderingControl', 'rc')}'
      '${_service(_cm, 'ConnectionManager', 'cm')}</serviceList></device></root>';

  static String _service(String type, String id, String path) =>
      '<service><serviceType>$type</serviceType><serviceId>urn:upnp-org:serviceId:$id</serviceId>'
      '<SCPDURL>/$path.xml</SCPDURL><controlURL>/$path/control</controlURL><eventSubURL>/$path/event</eventSubURL></service>';

  static String _scpd(String path) {
    final actions = switch (path) {
      '/avt.xml' => [
        'SetAVTransportURI',
        'Play',
        'Pause',
        'Stop',
        'Seek',
        'GetTransportInfo', //
        'GetPositionInfo',
        'GetMediaInfo',
        'GetTransportSettings',
        'GetCurrentTransportActions',
      ],
      '/rc.xml' => ['GetVolume', 'SetVolume', 'GetMute', 'SetMute'],
      _ => [
        'GetProtocolInfo',
        'GetCurrentConnectionIDs',
        'GetCurrentConnectionInfo',
      ],
    };
    return '<?xml version="1.0"?><scpd xmlns="urn:schemas-upnp-org:service-1-0">'
        '<specVersion><major>1</major><minor>0</minor></specVersion><actionList>'
        '${actions.map((a) => '<action><name>$a</name></action>').join()}</actionList>'
        '<serviceStateTable><stateVariable sendEvents="yes"><name>LastChange</name>'
        '<dataType>string</dataType></stateVariable></serviceStateTable></scpd>';
  }

  static Future<InternetAddress> _lanAddress() async {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in ifs) {
      for (final a in i.addresses) {
        if (!a.isLoopback && isLocalNetworkHost(a.address)) return a;
      }
    }
    return InternetAddress.loopbackIPv4;
  }
}

/// What the renderer accepts (the engine plays far more; these are the
/// DLNA-declared ones control points look for).
const protocolInfoSink =
    'http-get:*:video/mp4:*,http-get:*:video/x-matroska:*,'
    'http-get:*:video/mpeg:*,http-get:*:video/webm:*,http-get:*:video/quicktime:*,'
    'http-get:*:audio/mpeg:*,http-get:*:audio/flac:*,http-get:*:audio/mp4:*,'
    'http-get:*:audio/x-wav:*,http-get:*:audio/ogg:*,http-get:*:image/jpeg:*,http-get:*:image/png:*';

/// `H:MM:SS` (UPnP time).
String formatUpnpTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

Duration? _parseTime(String t) {
  final m = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?$')
      .firstMatch(t.trim());
  if (m == null) return null;
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
  );
}

final class _Subscription {
  _Subscription(this.callback, this.service, this.expires);

  final Uri callback;

  /// `avt` or `rc`.
  final String service;
  DateTime expires;

  /// Next SEQ (GENA event key), per subscription, starting at 0.
  int seq = 0;

  /// Delivery chain: one NOTIFY in flight per subscription, in order.
  Future<void> tail = Future.value();
}
