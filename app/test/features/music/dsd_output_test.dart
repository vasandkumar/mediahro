import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/player/dsd_output.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/ui/extras.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'music_test_support.dart';

/// AUD-043: "native DSD" is offered only after the OS grants a bit-perfect
/// path at the DoP rate on a DAC that advertises one.
void main() {
  late LibraryDatabase db;
  late _Output output;

  const dac = AudioDevice(
    id: '17',
    name: 'Fiio KA3',
    kind: AudioDeviceKind.usb,
    supportsExclusive: true,
    sampleRates: [44100, 96000, 176400, 352800],
  );
  const dacEngine = EngineAudioDevice(id: 'aaudio/17', name: 'Fiio KA3');

  setUp(() {
    db = LibraryDatabase.memory();
    output = _Output([dac]);
  });
  tearDown(() => db.close());

  DsdOutputGate gate() => DsdOutputGate(output: output, prefs: MusicPrefs(db));

  group('AUD-043 the offer', () {
    test('AUD-043 a DAC with a DoP rate and a bit-perfect grant is offered, '
        'and the grant is released after the probe', () async {
      expect((await gate().offerFor(dacEngine))?.id, '17');
      expect(output.requests.single, (id: '17', rate: dsd64DopRate, bits: 24));
      expect(output.released, 1);
    });

    test('AUD-043 no offer without a grant at the DoP rate and 24 bits, '
        'for a device without a DoP rate, or when the OS errors', () async {
      for (final grant in [
        const AudioPathGrant(bitPerfect: false),
        const AudioPathGrant(bitPerfect: true, sampleRate: 96000, bitDepth: 24),
        const AudioPathGrant(
          bitPerfect: true,
          sampleRate: dsd64DopRate,
          bitDepth: 16,
        ),
      ]) {
        output.grant = grant;
        expect(await gate().offerFor(dacEngine), isNull, reason: '$grant');
      }
      output
        ..grant = const AudioPathGrant(bitPerfect: true)
        ..throws = true;
      expect(await gate().offerFor(dacEngine), isNull);
      output.throws = false;
      expect(await gate().offerFor(dacEngine), isNotNull);

      output.osDevices = [
        const AudioDevice(
          id: '17',
          name: 'Fiio KA3',
          kind: AudioDeviceKind.usb,
          supportsExclusive: true,
          sampleRates: [44100, 96000, 192000],
        ),
      ];
      expect(await gate().offerFor(dacEngine), isNull);
      output.osDevices = [
        const AudioDevice(
          id: '17',
          name: 'Fiio KA3',
          kind: AudioDeviceKind.usb,
          sampleRates: [176400],
        ),
      ];
      expect(await gate().offerFor(dacEngine), isNull);
    });

    test('AUD-043 the system default and an unknown device are never '
        'offered; the engine device maps to the OS device by id, then by '
        'name', () async {
      expect(
        await gate().offerFor(
          const EngineAudioDevice(
            id: 'auto',
            name: 'Autoselect',
            isDefault: true,
          ),
        ),
        isNull,
      );
      expect(
        await gate().offerFor(
          const EngineAudioDevice(id: 'aaudio/99', name: 'Unknown'),
        ),
        isNull,
      );
      expect(
        (await gate().offerFor(
          const EngineAudioDevice(id: 'aaudio/x', name: ' fiio ka3 '),
        ))?.id,
        '17',
      );
    });

    test('AUD-043 the config lists dop and goes exclusive only with native '
        'DSD on', () {
      final on = DsdOutputGate.config('aaudio/17', nativeDsd: true);
      expect(on.deviceId, 'aaudio/17');
      expect(on.exclusive, isTrue);
      expect(on.nativeDsd, isTrue);
      expect(on.passthroughCodecs, ['dop']);
      final off = DsdOutputGate.config('aaudio/17', nativeDsd: false);
      expect(off.exclusive, isFalse);
      expect(off.nativeDsd, isFalse);
      expect(off.passthroughCodecs, isEmpty);
    });

    test('AUD-043 the choice is saved and restored on the engine', () async {
      final engine = ScriptedMusicEngine();
      await gate().restore(engine);
      expect(engine.audioOutputs, isEmpty);
      await gate().save('aaudio/17');
      expect(await gate().savedDevice(), 'aaudio/17');
      await gate().restore(engine);
      expect(engine.audioOutputs.single.passthroughCodecs, ['dop']);
      await gate().save(null);
      expect(await gate().savedDevice(), isNull);
    });
  });

  group('AUD-043 the output sheet', () {
    late ScriptedMusicEngine engine;
    late Directory data;

    setUp(() {
      engine = ScriptedMusicEngine()
        ..devices = const [
          EngineAudioDevice(id: 'auto', name: 'Autoselect', isDefault: true),
          dacEngine,
        ];
      data = Directory.systemTemp.createTempSync('c2_dsd');
    });
    tearDown(() {
      try {
        data.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort on Windows.
      }
    });

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryDatabaseProvider.overrideWithValue(db),
            appDataDirectoryProvider.overrideWithValue(data),
            sourceResolverProvider.overrideWithValue(
              localMusicFiles(db).resolver,
            ),
            audioOutputProvider.overrideWithValue(output),
            playbackEngineFactoryProvider.overrideWithValue((_) => engine),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showOutputSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testWidgets('AUD-043 native DSD appears only after the DAC is chosen '
        'and the OS grants bit-perfect; the switch turns DoP on and off', (
      tester,
    ) async {
      await openSheet(tester);
      expect(find.text('Native DSD'), findsNothing);
      await tester.tap(find.text('Fiio KA3'));
      await _settle(tester);
      expect(find.text('Native DSD'), findsOneWidget);
      // Choosing the DAC alone never turns DoP on.
      expect(engine.audioOutputs.last.nativeDsd, isFalse);
      expect(engine.audioOutputs.last.deviceId, 'aaudio/17');

      await tester.tap(find.text('Native DSD'));
      await _settle(tester);
      final on = engine.audioOutputs.last;
      expect(on.deviceId, 'aaudio/17');
      expect(on.exclusive, isTrue);
      expect(on.passthroughCodecs, ['dop']);
      expect(await tester.runAsync(gate().savedDevice), 'aaudio/17');

      await tester.tap(find.text('Native DSD'));
      await _settle(tester);
      expect(engine.audioOutputs.last.nativeDsd, isFalse);
      expect(await tester.runAsync(gate().savedDevice), isNull);

      // The system default hides the switch again.
      await tester.tap(find.text('System default'));
      await _settle(tester);
      expect(find.text('Native DSD'), findsNothing);
    });

    testWidgets('AUD-043 a DAC the OS will not give a bit-perfect path '
        'never gets the switch', (tester) async {
      output.grant = const AudioPathGrant(bitPerfect: false);
      await openSheet(tester);
      await tester.tap(find.text('Fiio KA3'));
      await _settle(tester);
      expect(find.text('Native DSD'), findsNothing);
      expect(engine.audioOutputs.any((c) => c.nativeDsd), isFalse);
    });
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final class _Output implements AudioOutputFacade {
  _Output(this.osDevices);

  List<AudioDevice> osDevices;
  AudioPathGrant grant = const AudioPathGrant(
    bitPerfect: true,
    sampleRate: dsd64DopRate,
    bitDepth: 24,
  );
  bool throws = false;
  final requests = <({String id, int rate, int? bits})>[];
  int released = 0;

  @override
  Future<List<AudioDevice>> devices() async => osDevices;

  @override
  Future<AudioPathGrant> requestBitPerfect(
    String deviceId, {
    required int sampleRate,
    int? bitDepth,
  }) async {
    requests.add((id: deviceId, rate: sampleRate, bits: bitDepth));
    if (throws) throw StateError('notFound');
    return grant;
  }

  @override
  Future<void> releaseBitPerfect() async => released++;

  @override
  Object? noSuchMethod(Invocation invocation) => Future<void>.value();
}
