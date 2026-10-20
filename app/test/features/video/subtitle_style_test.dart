import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations_en.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sheets.dart';
import 'package:mediahro/features/video/subtitles/subtitle_style.dart';
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
}
