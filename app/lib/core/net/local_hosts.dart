import 'dart:async';
import 'dart:io';

/// [host] as the network stack would see it: lower case, without brackets, a
/// zone id (`fe80::1%eth0`) or trailing dots (`localhost.` is `localhost`).
String normalizeHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  final zone = h.indexOf('%');
  if (zone >= 0) h = h.substring(0, zone);
  while (h.endsWith('.')) {
    h = h.substring(0, h.length - 1);
  }
  return h;
}

/// The four bytes of [host] when it is an IPv4 address written in any form
/// the system resolver accepts (`127.1`, `2130706433`, `0x7f000001`,
/// `0177.0.0.1`), else null (a name, or an IPv6 address).
List<int>? parseIPv4Loose(String host) {
  final parts = host.split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final values = <int>[];
  for (final p in parts) {
    if (p.isEmpty) return null;
    int? v;
    if (p.startsWith('0x') || p.startsWith('0X')) {
      v = p.length > 2 ? int.tryParse(p.substring(2), radix: 16) : null;
    } else if (p.length > 1 && p.startsWith('0')) {
      v = RegExp(r'^[0-7]+$').hasMatch(p) ? int.tryParse(p, radix: 8) : null;
    } else if (RegExp(r'^[0-9]+$').hasMatch(p)) {
      v = int.tryParse(p);
    }
    if (v == null) return null;
    values.add(v);
  }
  for (var i = 0; i < values.length - 1; i++) {
    if (values[i] > 255) return null;
  }
  final last = values.last;
  final room = 1 << (8 * (5 - values.length));
  if (last >= room) return null;
  var n = last;
  for (var i = 0; i < values.length - 1; i++) {
    n += values[i] << (8 * (3 - i));
  }
  return [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/// Raw bytes of [host] when it is an IP address in any accepted form.
({List<int> bytes, bool v6})? parseHostAddress(String host) {
  final h = normalizeHost(host);
  final v4 = parseIPv4Loose(h);
  if (v4 != null) return (bytes: v4, v6: false);
  if (!h.contains(':')) return null;
  final ip = InternetAddress.tryParse(h);
  if (ip == null || ip.type != InternetAddressType.IPv6) return null;
  return (bytes: ip.rawAddress, v6: true);
}

bool _privateV4(List<int> b) =>
    b[0] == 10 ||
    b[0] == 127 ||
    (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
    (b[0] == 192 && b[1] == 168) ||
    (b[0] == 169 && b[1] == 254) ||
    (b[0] == 100 && b[1] >= 64 && b[1] <= 127); // CGNAT (Tailscale etc.)

/// Private, link-local and loopback addresses and `.local` names: the
/// listener's own network, which LAN discovery may reach. Addresses are
/// parsed the way the resolver does, so `127.1` and `0x7f000001` count.
bool isLocalNetworkHost(String host) {
  final h = normalizeHost(host);
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.localhost')) {
    return true;
  }
  final a = parseHostAddress(h);
  if (a == null) return false;
  final b = a.bytes;
  if (!a.v6) return _privateV4(b);
  if (_allZero(b, 15) && b[15] == 1) return true; // ::1
  if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return true; // fe80::/10
  return (b[0] & 0xFE) == 0xFC; // fc00::/7 unique local
}

bool _allZero(List<int> b, int n) {
  for (var i = 0; i < n; i++) {
    if (b[i] != 0) return false;
  }
  return true;
}

bool _nonPublicBytes(List<int> b, {required bool v6}) {
  if (!v6) {
    return _privateV4(b) ||
        b[0] == 0 || // 0.0.0.0/8, unspecified
        b[0] >= 224 || // multicast, reserved, broadcast
        (b[0] == 192 && b[1] == 0 && b[2] == 0) ||
        (b[0] == 198 && (b[1] == 18 || b[1] == 19));
  }
  if (_allZero(b, 12)) return true; // ::, ::1 and IPv4-compatible
  if (_allZero(b, 10) && b[10] == 0xFF && b[11] == 0xFF) {
    return true; // IPv4-mapped, whatever it maps
  }
  if (b[0] == 0xFF) return true; // multicast
  if (b[0] == 0xFE && (b[1] & 0xC0) != 0) return true; // fe80::/9: link, site
  if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7
  if (b[0] == 0x00 &&
      b[1] == 0x64 &&
      b[2] == 0xFF &&
      b[3] == 0x9B &&
      _allZero(b.sublist(4), 8)) {
    return _nonPublicBytes(b.sublist(12), v6: false); // NAT64
  }
  if (b[0] == 0x20 && b[1] == 0x02) {
    return _nonPublicBytes(b.sublist(2, 6), v6: false); // 6to4
  }
  return false;
}

/// Whether [host] is somewhere a web page must not send the app to: the
/// listener's own network, loopback, unspecified, IPv4-mapped and reserved
/// addresses (in any spelling), `localhost`, `.local` names and single-label
/// names (which a router or search domain may resolve to a private address).
/// A name needs [resolvesToNonPublic] too: this does not look names up.
bool isNonPublicHost(String host) {
  final h = normalizeHost(host);
  if (h.isEmpty) return true;
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.localhost')) {
    return true;
  }
  final a = parseHostAddress(h);
  if (a != null) return _nonPublicBytes(a.bytes, v6: a.v6);
  if (h.contains(':')) return true; // an IPv6 form nobody can parse
  return !h.contains('.');
}

/// [isNonPublicHost], and for a name, whether any address it resolves to is
/// non-public (a public-looking name that points inside). A name that cannot
/// be resolved (no answer, an error, a timeout, no addresses) counts as
/// non-public too: an address nobody could check is not one to follow. A name
/// can still resolve differently when the connection is made (DNS rebinding:
/// the gateway connects separately).
Future<bool> resolvesToNonPublic(
  String host, {
  Future<List<InternetAddress>> Function(String host) lookup = _systemLookup,
}) async {
  final h = normalizeHost(host);
  if (isNonPublicHost(h)) return true;
  if (parseHostAddress(h) != null) return false;
  try {
    final addresses = await lookup(h).timeout(const Duration(seconds: 5));
    return addresses.isEmpty ||
        addresses.any(
          (a) => _nonPublicBytes(
            a.rawAddress,
            v6: a.type == InternetAddressType.IPv6,
          ),
        );
  } on Object {
    return true;
  }
}

/// The private-network hosts a feed's requests may reach: its own host when
/// the listener gave a host on their own network (an address or `.local`
/// name), nothing for a feed on the internet. A feed on the internet is
/// checked like any other hop on every request, so it cannot be repointed at
/// the listener's network.
Set<String> trustedFeedHosts(String feedHost) {
  final h = normalizeHost(feedHost);
  return isLocalNetworkHost(h) ? {h} : const {};
}

Future<List<InternetAddress>> _systemLookup(String host) =>
    InternetAddress.lookup(host);
