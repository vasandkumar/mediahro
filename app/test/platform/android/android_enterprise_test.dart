import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_enterprise.dart';
import 'package:mediahro/platform/android/gen/enterprise_api.pigeon.dart';
import 'package:mediahro/platform/enterprise.dart';

/// The Dart half of lane C4a's managed configuration and kiosk.
final class _FakeManaged extends ManagedConfigHostApi {
  @override
  Future<ManagedSnapshotMsg> read() async => ManagedSnapshotMsg(
    entries: [
      ManagedEntryMsg(
        key: 'kiosk',
        kind: ManagedKindMsg.boolean,
        boolValue: true,
      ),
      ManagedEntryMsg(
        key: 'playlist_url',
        kind: ManagedKindMsg.string,
        stringValue: 'https://example.test/list.m3u',
      ),
      ManagedEntryMsg(
        key: 'allowed_sources',
        kind: ManagedKindMsg.list,
        listValue: ['smb', 'sftp'],
      ),
      ManagedEntryMsg(
        key: 'volume_cap',
        kind: ManagedKindMsg.integer,
        intValue: 80,
      ),
      // A malformed entry (kind without its value) is dropped.
      ManagedEntryMsg(key: 'broken', kind: ManagedKindMsg.string),
    ],
  );
}

final class _FakeKiosk extends KioskHostApi {
  final calls = <String>[];
  bool bootSupported = true;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> isActive() async => false;

  @override
  Future<void> enter() async => calls.add('enter');

  @override
  Future<void> exit() async => calls.add('exit');

  @override
  Future<void> setStartOnBoot(bool enabled) async {
    if (!bootSupported) {
      throw PlatformException(code: 'unsupported', message: 'enterprise only');
    }
    calls.add('boot:$enabled');
  }
}

void main() {
  test('B2B-001 restrictions map to typed managed values', () async {
    final m = await AndroidManagedConfig(api: _FakeManaged()).read();
    expect(m.keys, ['kiosk', 'playlist_url', 'allowed_sources', 'volume_cap']);
    expect((m['kiosk']! as ManagedBool).value, isTrue);
    expect(
      (m['playlist_url']! as ManagedString).value,
      'https://example.test/list.m3u',
    );
    expect((m['allowed_sources']! as ManagedList).values, ['smb', 'sftp']);
    expect((m['volume_cap']! as ManagedInt).value, 80);
  });

  test('B2B-001 a restrictions change arrives as a new map', () async {
    final events = StreamController<ManagedSnapshotMsg>();
    addTearDown(() => unawaited(events.close()));
    final managed = AndroidManagedConfig(
      api: _FakeManaged(),
      events: () => events.stream,
    );
    final next = managed.changes.first;
    events.add(
      ManagedSnapshotMsg(
        entries: [
          ManagedEntryMsg(
            key: 'telemetry_off',
            kind: ManagedKindMsg.boolean,
            boolValue: true,
          ),
        ],
      ),
    );
    expect(((await next)['telemetry_off']! as ManagedBool).value, isTrue);
  });

  test('B2B-002 kiosk enter, exit and state changes', () async {
    final api = _FakeKiosk();
    final states = StreamController<bool>();
    addTearDown(() => unawaited(states.close()));
    final kiosk = AndroidKiosk(api: api, events: () => states.stream);
    expect(await kiosk.isSupported(), isTrue);
    await kiosk.enter();
    await kiosk.exit();
    expect(api.calls, ['enter', 'exit']);
    final seen = <bool>[];
    final sub = kiosk.isActive.listen(seen.add);
    states
      ..add(false)
      ..add(false)
      ..add(true);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [false, true]);
  });

  test('B2B-002 start on boot is enterprise only', () async {
    final api = _FakeKiosk();
    final kiosk = AndroidKiosk(api: api);
    await kiosk.setStartOnBoot(enabled: true);
    expect(api.calls, ['boot:true']);
    api.bootSupported = false;
    await expectLater(
      kiosk.setStartOnBoot(enabled: true),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
