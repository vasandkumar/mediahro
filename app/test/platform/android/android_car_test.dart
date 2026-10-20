import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_car.dart';
import 'package:mediahro/platform/android/gen/car_api.pigeon.dart';
import 'package:mediahro/platform/car_and_alarms.dart';

/// The Dart half of lane C4a's Android Auto browsing and alarms.
final class _FakeBrowse extends MediaBrowseHostApi {
  final calls = <String>[];

  @override
  Future<void> registered() async => calls.add('registered');

  @override
  Future<void> notifyChildrenChanged(String nodeId) async =>
      calls.add('changed:$nodeId');
}

final class _FakeAlarms extends AlarmHostApi {
  ScheduledAlarmMsg? scheduled;

  @override
  Future<void> schedule(ScheduledAlarmMsg alarm) async => scheduled = alarm;
}

final class _Provider implements MediaBrowseProvider {
  final played = <String>[];

  @override
  Future<List<MediaBrowseNode>> children(String nodeId, {int page = 0}) async =>
      [
        MediaBrowseNode(
          id: '$nodeId/$page',
          title: 'T',
          subtitle: 'S',
          artworkUri: Uri.parse('file:///art/1.jpg'),
          playable: true,
          browsable: false,
        ),
      ];

  @override
  Future<List<MediaBrowseNode>> search(String query) async => [];

  @override
  Future<void> play(String nodeId) async => played.add(nodeId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MUS-013 registering answers native browse requests', () async {
    final api = _FakeBrowse();
    final provider = _Provider();
    await AndroidMediaBrowse(api: api).register(provider);
    expect(api.calls, ['registered']);

    // Native calls Dart over MediaBrowseFlutterApi's channel.
    const codec = MediaBrowseFlutterApi.pigeonChannelCodec;
    final reply = await TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          'dev.flutter.pigeon.mediahro.MediaBrowseFlutterApi.children',
          codec.encodeMessage(<Object?>['root', 2]),
          (_) {},
        );
    final decoded = codec.decodeMessage(reply)! as List<Object?>;
    final nodes = (decoded.single! as List<Object?>).cast<MediaBrowseNodeMsg>();
    expect(nodes.single.id, 'root/2');
    expect(nodes.single.artworkUri, 'file:///art/1.jpg');
    expect(nodes.single.playable, isTrue);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'dev.flutter.pigeon.mediahro.MediaBrowseFlutterApi.play',
          codec.encodeMessage(<Object?>['album:1']),
          (_) {},
        );
    expect(provider.played, ['album:1']);
  });

  test('MUS-011 alarms carry id, time and label; fired maps ids', () async {
    final api = _FakeAlarms();
    final events = StreamController<AlarmFiredMsg>();
    final alarms = AndroidAlarms(api: api, events: () => events.stream);
    final at = DateTime(2026, 10, 21, 7, 30);
    await alarms.schedule(ScheduledAlarm(id: 'a1', at: at, label: 'Wake'));
    expect(api.scheduled!.id, 'a1');
    expect(api.scheduled!.atMs, at.millisecondsSinceEpoch);
    expect(api.scheduled!.label, 'Wake');
    final got = <String>[];
    final sub = alarms.fired.listen(got.add);
    events.add(AlarmFiredMsg(id: 'a1'));
    await pumpEventQueue();
    await sub.cancel();
    expect(got, ['a1']);
  });
}
