import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations_en.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sheets.dart';
import 'package:mediahro/features/video/subtitles/subtitle_style.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import '../../../integration_test/support/c1_engine.dart';
import '../../helpers.dart';

void main() {
  late SettingsStore settings;

  setUp(() async => settings = await memoryStore());

  SubtitleStyle style({CaptionPrefs? system}) =>
      subtitleStyleFor(settings.snapshot, system: system);

  group('SUB-014 styling', () {
    test('SUB-014 "System" everywhere leaves the engine defaults', () {
      final s = style();
      expect(s.font, isNull);
      expect(s.scale, isNull);
      expect(s.colorArgb, isNull);
      expect(s.backgroundArgb, isNull);
      expect(s.verticalPosition, isNull);
      expect(s.borderStyle, SubtitleBorderStyle.outlineAndShadow);
      expect(s.overrideAssStyles, isFalse);
    });

    test('SUB-014 every choice reaches the engine style', () {
      settings
        ..set(SubtitleSettings.size, SubSize.large)
        ..set(SubtitleSettings.color, SubColor.yellow)
        ..set(SubtitleSettings.outline, SubOutline.thick)
        ..set(SubtitleSettings.background, SubBackground.opaque)
        ..set(SubtitleSettings.font, SubFont.serif)
        ..set(SubtitleSettings.position, SubPosition.top)
        ..set(SubtitleSettings.align, SubAlign.left)
        ..set(SubtitleSettings.overrideAss, true);
      final s = style();
      expect(s.scale, 1.3);
      expect(s.colorArgb, 0xFFFFE600);
      expect(s.outlineWidth, 5);
      expect(s.backgroundArgb, 0xFF000000);
      expect(s.borderStyle, SubtitleBorderStyle.backgroundBox);
      expect(s.font, 'serif');
      expect(s.verticalPosition, 100);
      expect(s.alignX, SubtitleAlignX.left);
      expect(s.overrideAssStyles, isTrue);
    });

    test('SUB-014 "System" takes the system caption style; choices win', () {
      const system = CaptionPrefs(
        scale: 1.5,
        foregroundArgb: 0xFF00FF00,
        backgroundArgb: 0x80000000,
        edgeWidth: 0,
        fontFamily: 'Atkinson',
      );
      var s = style(system: system);
      expect(s.scale, 1.5);
      expect(s.colorArgb, 0xFF00FF00);
      expect(s.backgroundArgb, 0x80000000);
      expect(s.borderStyle, SubtitleBorderStyle.backgroundBox);
      expect(s.outlineWidth, 0);
      expect(s.font, 'Atkinson');
      settings
        ..set(SubtitleSettings.size, SubSize.small)
        ..set(SubtitleSettings.background, SubBackground.none);
      s = style(system: system);
      expect(s.scale, 0.75);
      expect(s.backgroundArgb, isNull);
      expect(s.borderStyle, SubtitleBorderStyle.outlineAndShadow);
    });
  });

  group('ADR-030 system caption style', () {
    test('ADR-030 the system style maps to the engine style', () {
      final prefs = captionPrefsFrom(
        const SystemCaptionStyle(
          enabled: true,
          scale: 1.5,
          foregroundArgb: 0xFFFFFF00,
          windowArgb: 0xCC000000,
          edge: CaptionEdge.dropShadow,
          fontFamily: 'Roboto',
        ),
      )!;
      expect(prefs.captionsOn, isTrue);
      final st = style(system: prefs);
      expect(st.scale, 1.5);
      expect(st.colorArgb, 0xFFFFFF00);
      expect(st.backgroundArgb, 0xCC000000);
      expect(st.borderStyle, SubtitleBorderStyle.backgroundBox);
      expect(st.shadowOffset, 2);
      expect(st.font, 'Roboto');
    });

    test('ADR-030 an unset edge keeps the engine outline', () {
      final prefs = captionPrefsFrom(const SystemCaptionStyle(enabled: false))!;
      final st = style(system: prefs);
      expect(st.outlineWidth, isNull);
      expect(st.scale, isNull);
      expect(prefs.captionsOn, isFalse);
      expect(captionPrefsFrom(null), isNull);
    });

    test('ADR-030 the provider follows the facade and its changes', () async {
      final facade = _Captions();
      final container = ProviderContainer(
        overrides: [captionStyleProvider.overrideWithValue(facade)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(captionPrefsProvider, (_, _) {});
      addTearDown(sub.close);
      // Waits for the emission itself rather than a fixed delay.
      Future<void> scale(double want) async {
        if (container.read(captionPrefsProvider)?.scale == want) return;
        final done = Completer<void>();
        final s = container.listen(captionPrefsProvider, (_, v) {
          if (v?.scale == want && !done.isCompleted) done.complete();
        });
        try {
          await done.future.timeout(const Duration(seconds: 30));
        } finally {
          s.close();
        }
      }

      await scale(1.25);
      expect(container.read(captionPrefsProvider)!.scale, 1.25);
      facade.change(const SystemCaptionStyle(enabled: true, scale: 2));
      await scale(2);
      expect(container.read(captionPrefsProvider)!.scale, 2);
    });

    test('ADR-030 without a facade there is no system style', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(captionPrefsProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(captionPrefsProvider), isNull);
    });
  });

  group('SUB-015 SUB-016 in the player', () {
    late RecordingEngine engine;
    late VideoMemory memory;
    late VideoPlayerController c;

    setUp(() async {
      engine = RecordingEngine();
      memory = await VideoMemory.open(MemoryVideoMemoryPersistence());
      c = VideoPlayerController(
        engine: engine,
        memory: memory,
        settings: settings,
      );
    });

    tearDown(() async {
      c.dispose();
      await engine.dispose();
    });

    PlayRequest req(String n) => PlayRequest.uri(Uri.parse('file:///v/$n.mkv'));

    test(
      'SUB-015 frame-rate conversion speeds are remembered per file',
      () async {
        await c.open(req('a'));
        final conv = fpsFactor((23.976, 25));
        await c.setSubtitleSpeed(conv);
        expect(engine.fake.subSpeed, conv);
        await c.open(req('b'));
        expect(c.subtitleSpeed, 1);
        await c.open(req('a'));
        expect(engine.fake.subSpeed, conv);
        expect(c.subtitleSpeed, conv);
      },
    );

    test('SUB-015 conversion labels', () {
      final l = AppLocalizationsEn();
      expect(subtitleSpeedLabel(l, 1), 'Normal');
      expect(
        subtitleSpeedLabel(l, fpsFactor((23.976, 25))),
        'From 23.976 to 25 fps',
      );
      expect(
        subtitleSpeedLabel(l, fpsFactor((25, 29.97))),
        'From 25 to 29.97 fps',
      );
    });

    test('SUB-016 second subtitles: own track and own delay', () async {
      await c.open(req('a'));
      await Future<void>.delayed(Duration.zero);
      final second = c.tracksOf(TrackType.subtitle).first;
      await c.selectSecondarySubtitle(second);
      expect(engine.selections.last, (
        TrackType.subtitle,
        second.id,
        SubtitleSlot.secondary,
      ));
      await c.setSecondarySubtitleDelay(const Duration(milliseconds: 1234));
      expect(engine.subDelays.last, (
        const Duration(milliseconds: 1250),
        SubtitleSlot.secondary,
      ));
      await c.setSecondarySubtitleDelay(const Duration(minutes: 5));
      expect(engine.subDelays.last.$1, const Duration(seconds: 60));
      await c.selectSecondarySubtitle(null);
      expect(engine.selections.last.$2, isNull);
    });
  });

  group('SUB-014 captions on in the system (docs/06 section 7)', () {
    late RecordingEngine engine;
    late VideoPlayerController c;
    var on = true;

    setUp(() async {
      on = true;
      engine = RecordingEngine(
        tracks: const [
          Track(id: 1, type: TrackType.video, width: 1920, height: 1080),
          Track(
            id: 1,
            type: TrackType.subtitle,
            language: 'en',
            isForced: true,
          ),
          Track(id: 2, type: TrackType.subtitle, language: 'de'),
          Track(id: 3, type: TrackType.subtitle, language: 'en'),
        ],
      );
      c = VideoPlayerController(
        engine: engine,
        memory: await VideoMemory.open(MemoryVideoMemoryPersistence()),
        settings: settings,
        systemLanguages: const ['en'],
        systemCaptionsOn: () => on,
      );
    });

    tearDown(() async {
      c.dispose();
      await engine.dispose();
    });

    test(
      'SUB-014 captions on: subtitles start in my language, not forced',
      () async {
        await c.open(PlayRequest.uri(Uri.parse('file:///v/a.mkv')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(engine.current.subtitleTrackId, 3);
      },
    );

    test('SUB-014 captions off: nothing is turned on', () async {
      on = false;
      await c.open(PlayRequest.uri(Uri.parse('file:///v/a.mkv')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engine.current.subtitleTrackId, isNull);
    });
  });
}

final class _Captions implements CaptionStyleFacade {
  final _changes = StreamController<SystemCaptionStyle>.broadcast();

  void change(SystemCaptionStyle s) => _changes.add(s);

  @override
  Future<SystemCaptionStyle?> current() async =>
      const SystemCaptionStyle(enabled: true, scale: 1.25);

  @override
  Stream<SystemCaptionStyle> get changes => _changes.stream;
}
