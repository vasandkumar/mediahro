import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mediahro.engine/audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('AUD-040 bit-perfect request carries the source format', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return {
        'applied': true,
        'bitPerfect': true,
        'sampleRate': 96000,
        'device': 'USB DAC',
      };
    });
    final r = await AudioBridge().prefer(
      bitPerfect: true,
      sampleRate: 96000,
      channels: 2,
      bitDepth: 24,
    );
    expect(seen!.method, 'prefer');
    expect(seen!.arguments, {
      'bitPerfect': true,
      'sampleRate': 96000,
      'channels': 2,
      'bitDepth': 24,
    });
    expect(r.applied && r.bitPerfect, isTrue);
    expect(r.sampleRate, 96000);
    expect(r.device, 'USB DAC');
  });

  test('AUD-006 a platform without the bridge reports not applied', () async {
    final r = await AudioBridge().prefer(bitPerfect: true, sampleRate: 44100);
    expect(r.applied, isFalse);
    expect(r.bitPerfect, isFalse);
  });
}
