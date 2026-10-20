import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_input.dart';
import 'package:mediahro/platform/android/gen/input_api.pigeon.dart';
import 'package:mediahro/platform/gamepad.dart';

/// The Dart half of lane C4a's accessibility preferences and gamepad (ADR-038).
final class _FakePrefs extends AccessibilityPrefsHostApi {
  bool requested = false;

  @override
  Future<bool> audioDescriptionRequested() async => requested;
}

final class _FakePads extends GamepadHostApi {
  @override
  Future<List<GamepadInfoMsg>> connected() async => [
    GamepadInfoMsg(id: 4, name: 'Xbox Wireless Controller', vendorId: 0x45e),
  ];
}

void main() {
  test('SYS-008 audio description preference and its changes', () async {
    final events = StreamController<bool>();
    addTearDown(() => unawaited(events.close()));
    final prefs = AndroidAccessibilityPrefs(
      api: _FakePrefs(),
      events: () => events.stream,
    );
    expect(await prefs.audioDescriptionRequested(), isFalse);
    final next = prefs.audioDescriptionChanges.first;
    events.add(true);
    expect(await next, isTrue);
  });

  test('SYS-009 connected controllers carry their names and ids', () async {
    final pad = AndroidGamepad(api: _FakePads());
    final list = await pad.connected();
    expect(list.single.id, 4);
    expect(list.single.name, 'Xbox Wireless Controller');
    expect(list.single.vendorId, 0x45e);
    expect(list.single.productId, isNull);
  });

  test('SYS-009 connect and disconnect events', () async {
    final events = StreamController<GamepadChangeMsg>();
    addTearDown(() => unawaited(events.close()));
    final pad = AndroidGamepad(
      api: _FakePads(),
      connectionEvents: () => events.stream,
    );
    final seen = <GamepadChange>[];
    final sub = pad.connections.listen(seen.add);
    events
      ..add(
        GamepadChangeMsg(
          added: true,
          gamepad: GamepadInfoMsg(id: 9, name: 'A'),
        ),
      )
      ..add(
        GamepadChangeMsg(
          added: false,
          gamepad: GamepadInfoMsg(id: 9, name: 'A'),
        ),
      );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.map((c) => c.kind), [
      GamepadConnectionKind.added,
      GamepadConnectionKind.removed,
    ]);
    expect(seen.first.gamepad.id, 9);
  });

  test('SYS-009 axis events map every axis', () async {
    final events = StreamController<GamepadAxisEventMsg>();
    addTearDown(() => unawaited(events.close()));
    final pad = AndroidGamepad(axisEvents: () => events.stream);
    final seen = <GamepadAxisEvent>[];
    final sub = pad.axes.listen(seen.add);
    for (final a in GamepadAxisMsg.values) {
      events.add(GamepadAxisEventMsg(deviceId: 4, axis: a, value: 0.5));
    }
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.map((e) => e.axis), GamepadAxis.values);
    expect(seen.every((e) => e.deviceId == 4 && e.value == 0.5), isTrue);
  });
}
