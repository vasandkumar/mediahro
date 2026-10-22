import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/net/local_hosts.dart';

/// PRIV-004: what counts as the listener's own network, in any spelling.
void main() {
  group('normalizeHost', () {
    test('lower case, no brackets, zone or trailing dots', () {
      expect(normalizeHost('Example.COM.'), 'example.com');
      expect(normalizeHost('[FE80::1%eth0]'), 'fe80::1');
      expect(normalizeHost('localhost..'), 'localhost');
    });
  });

  group('parseIPv4Loose', () {
    test('every form the resolver accepts', () {
      expect(parseIPv4Loose('127.0.0.1'), [127, 0, 0, 1]);
      expect(parseIPv4Loose('127.1'), [127, 0, 0, 1]);
      expect(parseIPv4Loose('2130706433'), [127, 0, 0, 1]);
      expect(parseIPv4Loose('0x7f000001'), [127, 0, 0, 1]);
      expect(parseIPv4Loose('0x7f.1'), [127, 0, 0, 1]);
      expect(parseIPv4Loose('0177.0.0.01'), [127, 0, 0, 1]);
      expect(parseIPv4Loose('192.168.257'), [192, 168, 1, 1]);
    });

    test('names and nonsense are not addresses', () {
      for (final h in const [
        'example.com',
        '1.2.3.4.5',
        '256.1.1.1',
        '1.2.3.65536',
        '4294967296',
        '08.1',
        '0x',
        '1..2',
        '',
        'a.1',
        '::1',
      ]) {
        expect(parseIPv4Loose(h), isNull, reason: h);
      }
    });
  });

  group('isNonPublicHost', () {
    test("the listener's own network, loopback and reserved ranges", () {
      for (final h in const [
        'localhost',
        'LOCALHOST.',
        'a.localhost',
        'nas.local',
        'nas.local.',
        'router',
        '127.0.0.1',
        '127.255.255.254',
        '127.1',
        '2130706433',
        '0x7f000001',
        '0177.0.0.1',
        '0.0.0.0',
        '0',
        '10.0.0.1',
        '10.255.255.255',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.0.1',
        '169.254.169.254',
        '100.64.0.1',
        '100.127.255.255',
        '224.0.0.1',
        '255.255.255.255',
        '192.0.0.8',
        '198.18.0.1',
        '[::1]',
        '::1',
        '::',
        '[::ffff:192.168.1.5]',
        '[::ffff:8.8.8.8]',
        '::ffff:c0a8:0105',
        '::192.168.1.5',
        'fc00::1',
        'fd12:3456::1',
        'fe80::1',
        'fe80::1%eth0',
        'febf::1',
        'fec0::1',
        'ff02::1',
        '64:ff9b::c0a8:105',
        '2002:c0a8:105::1',
      ]) {
        expect(isNonPublicHost(h), isTrue, reason: h);
      }
    });

    test('public addresses and names are not', () {
      for (final h in const [
        'example.com',
        'feeds.example.com.',
        'cdn-1.example.co.uk',
        '8.8.8.8',
        '93.184.216.34',
        '172.15.255.255',
        '172.32.0.1',
        '100.63.255.255',
        '100.128.0.1',
        '169.253.1.1',
        '192.169.0.1',
        '223.255.255.255',
        '2606:2800:220:1:248:1893:25c8:1946',
        '2001:4860:4860::8888',
        '64:ff9b::808:808',
        '2002:808:808::1',
      ]) {
        expect(isNonPublicHost(h), isFalse, reason: h);
      }
    });
  });

  group('isLocalNetworkHost (LAN discovery)', () {
    test('the same spellings count; unspecified and mapped addresses are not '
        'LAN hosts', () {
      for (final h in const [
        'localhost.',
        'nas.local',
        '127.1',
        '0x7f000001',
        '192.168.1.20',
        '10.0.0.1',
        '172.16.5.5',
        '169.254.1.1',
        '100.100.1.1',
        '::1',
        '[fe80::1]',
        'fd00::1',
      ]) {
        expect(isLocalNetworkHost(h), isTrue, reason: h);
      }
      for (final h in const [
        'example.com',
        '8.8.8.8',
        '172.32.0.1',
        '0.0.0.0',
        '::',
        '::ffff:192.168.1.5',
        'router',
      ]) {
        expect(isLocalNetworkHost(h), isFalse, reason: h);
      }
    });
  });

  group('resolvesToNonPublic', () {
    Future<List<InternetAddress>> Function(String) answers(
      Map<String, List<String>> m,
    ) =>
        (h) async => [
          for (final a in m[h] ?? ['93.184.216.34']) InternetAddress(a),
        ];

    test(
      'a name is refused when any address it resolves to is inside',
      () async {
        final lookup = answers({
          'inside.example': ['10.0.0.9'],
          'mixed.example': ['93.184.216.34', '192.168.1.1'],
          'v6.example': ['fd00::5'],
          'mapped.example': ['::ffff:10.0.0.1'],
          'zero.example': ['0.0.0.0'],
        });
        for (final h in const [
          'inside.example',
          'mixed.example',
          'v6.example',
          'mapped.example',
          'zero.example',
        ]) {
          expect(
            await resolvesToNonPublic(h, lookup: lookup),
            isTrue,
            reason: h,
          );
        }
        expect(
          await resolvesToNonPublic('fine.example', lookup: lookup),
          isFalse,
        );
      },
    );

    test(
      'addresses and obviously local names are decided without a lookup',
      () async {
        Future<List<InternetAddress>> never(String h) =>
            throw StateError('looked up $h');
        expect(await resolvesToNonPublic('127.1', lookup: never), isTrue);
        expect(await resolvesToNonPublic('nas.local', lookup: never), isTrue);
        expect(await resolvesToNonPublic('8.8.8.8', lookup: never), isFalse);
      },
    );

    test('a name that cannot be checked is refused: no answer, no '
        'addresses, an error', () async {
      expect(
        await resolvesToNonPublic(
          'gone.example',
          lookup: (h) async => throw const SocketException('no such host'),
        ),
        isTrue,
      );
      expect(
        await resolvesToNonPublic('empty.example', lookup: (h) async => []),
        isTrue,
      );
      expect(
        await resolvesToNonPublic(
          'slow.example',
          lookup: (h) => Completer<List<InternetAddress>>().future,
        ),
        isTrue,
      );
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('trustedFeedHosts', () {
    test("only a host on the listener's own network is trusted for its "
        'feed; a feed on the internet is checked on every hop', () {
      expect(trustedFeedHosts('192.168.1.9'), {'192.168.1.9'});
      expect(trustedFeedHosts('NAS.local.'), {'nas.local'});
      expect(trustedFeedHosts('localhost'), {'localhost'});
      expect(trustedFeedHosts('127.1'), {'127.1'});
      expect(trustedFeedHosts('feeds.example.com'), isEmpty);
      expect(trustedFeedHosts('8.8.8.8'), isEmpty);
      // Not "local" in the LAN sense, so not trusted either.
      expect(trustedFeedHosts('0.0.0.0'), isEmpty);
      expect(trustedFeedHosts('router'), isEmpty);
    });
  });
}
