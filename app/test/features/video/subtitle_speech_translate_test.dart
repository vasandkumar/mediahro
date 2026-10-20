import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/subtitles/subtitle_speech.dart';
import 'package:mediahro/features/video/subtitles/subtitle_text_source.dart';
import 'package:mediahro/features/video/subtitles/subtitle_translation.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

import '../../../integration_test/support/c1_engine.dart';
import '../../../integration_test/support/c1_platform.dart';
import '../../helpers.dart';

const _srt =
    '1\n00:00:01,000 --> 00:00:03,000\nHello\nthere\n\n'
    '2\n00:00:05,000 --> 00:00:07,000\nSecond line\n';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  late Directory dir;
  late RecordingEngine engine;
  late SettingsStore settings;
  late VideoPlayerController c;
  late SubtitleTextSource text;

  // Lets earlier engine events land first, so a condition that was true
  // before the last action can't pass early.
  Future<void> wait(bool Function() done) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('c1_tts');
    final file = File('${dir.path}/film.en.srt')..writeAsStringSync(_srt);
    engine = RecordingEngine(
      tracks: const [
        Track(id: 1, type: TrackType.video, width: 1920, height: 1080),
        Track(id: 1, type: TrackType.subtitle, codec: 'ass', language: 'ja'),
      ],
    );
    settings = await memoryStore();
    c = VideoPlayerController(
      engine: engine,
      memory: await VideoMemory.open(MemoryVideoMemoryPersistence()),
      settings: settings,
    );
    text = SubtitleTextSource(c);
    await c.open(PlayRequest.uri(Uri.parse('file:///v/film.mkv')));
    await c.addSubtitleFile(file.uri, language: 'en', select: true);
    await wait(() => text.document != null);
  });

  tearDown(() async {
    text.dispose();
    c.dispose();
    await engine.dispose();
    dir.deleteSync(recursive: true);
  });

  group('SUB-040 read subtitles aloud', () {
    test('SUB-040 the line at the play head, with delay and speed', () async {
      expect(text.available, isTrue);
      await c.seekTo(ms(2000));
      await wait(() => text.cue != null);
      expect(text.cue!.plainText, 'Hello\nthere');
      await c.setSubtitleDelay(ms(3000));
      await c.seekTo(ms(4500));
      await wait(() => text.cue?.plainText == 'Hello\nthere');
      expect(text.cue!.plainText, 'Hello\nthere', reason: 'shown 3 s later');
      await c.setSubtitleDelay(Duration.zero);
      await c.setSubtitleSpeed(2);
      await c.seekTo(ms(11000));
      await wait(() => text.cue?.plainText == 'Second line');
      expect(text.cue!.plainText, 'Second line', reason: 'twice as late');
    });

    test(
      'SUB-040 each new line is spoken once in the track language',
      () async {
        final speech = FakeSpeech();
        final speaker = SubtitleSpeaker(
          source: text,
          speech: speech,
          settings: settings,
        )..enabled = true;
        addTearDown(speaker.dispose);
        settings.set(SpeechSettings.rate, 1.25);
        await c.seekTo(ms(1500));
        await wait(() => speech.spoken.isNotEmpty);
        await c.seekTo(ms(2000));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(speech.spoken, [('Hello there', 'en', 1.25)]);
        await c.seekTo(ms(5500));
        await wait(() => speech.spoken.length == 2);
        expect(speech.spoken.last.$1, 'Second line');
        expect(speech.stops, greaterThanOrEqualTo(2), reason: 'interrupts');
      },
    );

    test('SUB-040 nothing is spoken while paused or when off', () async {
      final speech = FakeSpeech();
      final speaker = SubtitleSpeaker(
        source: text,
        speech: speech,
        settings: settings,
      );
      addTearDown(speaker.dispose);
      await c.seekTo(ms(1500));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(speech.spoken, isEmpty, reason: 'off by default');
      speaker.enabled = true;
      await engine.pause();
      await c.seekTo(ms(5500));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(speech.spoken, isEmpty);
    });

    test('SUB-040 built-in tracks cannot be read yet', () async {
      await c.selectSubtitle(c.tracksOf(TrackType.subtitle).first);
      await Future<void>.delayed(Duration.zero);
      expect(text.available, isFalse);
      expect(await text.load(), isNull);
    });
  });

  group('SUB-053 translation', () {
    test('SUB-053 pairs, consent before download, times kept', () async {
      final facade = FakeTranslation();
      final t = SubtitleTranslator(facade, batch: 1);
      expect(await t.sources(), containsAll(['en', 'de']));
      expect(await t.targetsFor('en'), ['de', 'fr']);
      expect(await t.needsDownload('en', 'de'), isTrue);
      await t.download('en', 'de');
      expect(facade.prepared, [('en', 'de')]);
      final doc = (await text.load())!;
      final progress = <double>[];
      final out = await t.translate(
        doc,
        from: 'en',
        to: 'de',
        onProgress: progress.add,
      );
      expect(out.cues.map((x) => x.text), [
        'de: Hello\nthere',
        'de: Second line',
      ]);
      expect(out.cues.first.start, doc.cues.first.start);
      expect(out.cues.last.end, doc.cues.last.end);
      expect(facade.batches, [1, 1]);
      expect(progress, [0.5, 1.0]);
    });

    test('SUB-053 a translator that drops lines is refused', () async {
      final t = SubtitleTranslator(_Dropping());
      final doc = (await text.load())!;
      expect(
        () => t.translate(doc, from: 'en', to: 'de'),
        throwsA(isA<StateError>()),
      );
    });

    test('SUB-053 the result is SRT for the player', () async {
      final doc = (await text.load())!;
      final out = await SubtitleTranslator(FakeTranslation(ready: true))
          .translate(doc, from: 'en', to: 'fr');
      final srt = const SrtParser().write(out);
      expect(srt, contains('fr: Second line'));
    });
  });
}

final class _Dropping extends FakeTranslation {
  @override
  Future<List<String>> translate(
    List<String> lines, {
    required String from,
    required String to,
  }) async => lines.skip(1).toList();
}
