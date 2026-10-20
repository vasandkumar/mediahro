import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/video/subtitles/editor/subtitle_editor_model.dart';
import 'package:mediahro/features/video/subtitles/editor/subtitle_editor_screen.dart';

const _srt =
    '1\n00:00:01,000 --> 00:00:02,000\nOne\n\n'
    '2\n00:00:03,000 --> 00:00:04,000\nTwo\n\n'
    '3\n00:00:10,000 --> 00:00:11,000\nThree\n';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('SUB-030 editor model', () {
    late SubtitleEditorModel m;

    setUp(() async {
      m = await SubtitleEditorModel.open('Film.en.srt', _bytes(_srt));
    });

    test('SUB-030 opens off the UI isolate and edits with undo/redo', () {
      expect(m.cues, hasLength(3));
      expect(m.dirty, isFalse);
      m.shift(ms(500));
      expect(m.cues.first.start, ms(1500));
      expect(m.dirty, isTrue);
      m.undo();
      expect(m.cues.first.start, ms(1000));
      m.redo();
      expect(m.cues.first.start, ms(1500));
    });

    test('SUB-030 shift only the selection', () {
      m
        ..toggle(1)
        ..shift(-ms(500));
      expect(m.cues[0].start, ms(1000));
      expect(m.cues[1].start, ms(2500));
    });

    test('SUB-030 resync by two points', () {
      m.resync(0, ms(2000), 2, ms(12000));
      expect(m.cues[0].start, ms(2000));
      expect(m.cues[2].start, ms(12000));
      expect(m.cues[1].start.inMilliseconds, closeTo(4222, 1));
    });

    test('SUB-030 split, merge, delete, add and edit', () {
      m.split(0, ms(1500));
      expect(m.cues, hasLength(4));
      m
        ..toggle(0)
        ..toggle(1)
        ..mergeSelected();
      expect(m.cues, hasLength(3));
      expect(m.cues.first.end, ms(2000));
      m
        ..clearSelection()
        ..toggle(2)
        ..deleteSelected();
      expect(m.cues.map((c) => c.text), ['One\nOne', 'Two']);
      final i = m.addAt(ms(6000));
      m.updateCue(i, text: 'New', end: ms(7000));
      expect(m.cues[i].text, 'New');
      expect(m.cues[i].end, ms(7000));
    });

    test('SUB-030 save as SRT, ASS and WebVTT', () {
      expect(m.nameFor(SaveFormat.ass), 'Film.en.ass');
      final ass = utf8.decode(m.export(SaveFormat.ass).sublist(3));
      expect(
        ass,
        contains('Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,One'),
      );
      final vtt = utf8.decode(m.export(SaveFormat.vtt).sublist(3));
      expect(vtt, startsWith('WEBVTT'));
      final srt = m.export(SaveFormat.srt);
      expect(srt.take(3), [0xEF, 0xBB, 0xBF]);
    });

    test('SUB-030 fix encoding re-reads the original bytes', () async {
      // "Привет" in Windows-1251: not UTF-8, so it first reads as 1252.
      final cyr = Uint8List.fromList([
        ...utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n'),
        0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x0A, //
      ]);
      final mm = await SubtitleEditorModel.open('ru.srt', cyr);
      expect(mm.cues.single.text, isNot('Привет'));
      await mm.reEncode('cp1251');
      expect(mm.cues.single.text, 'Привет');
      expect(mm.charset, 'cp1251');
      mm.undo();
      expect(mm.cues.single.text, isNot('Привет'));
    });
  });

  group('SUB-030 editor screen', () {
    Future<(SubtitleEditorModel, List<(String, Uint8List)>)> pump(
      WidgetTester tester, {
      Duration Function()? position,
    }) async {
      final m = (await tester.runAsync(
        () => SubtitleEditorModel.open('Film.srt', _bytes(_srt)),
      ))!;
      final saved = <(String, Uint8List)>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SubtitleEditorScreen(
            model: m,
            position: position,
            seek: (_) {},
            save: (name, bytes) async {
              saved.add((name, bytes));
              return '/subs/$name';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (m, saved);
    }

    testWidgets('SUB-030 shift everything from the toolbar', (tester) async {
      final (m, _) = await pump(tester);
      expect(find.text('One'), findsOneWidget);
      await tester.tap(find.text('Shift all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('500 ms'));
      await tester.pumpAndSettle();
      expect(m.cues.first.start, ms(1500));
      expect(find.text('00:00:01,500 to 00:00:02,500'), findsOneWidget);
    });

    testWidgets('SUB-030 edit a line; save as ASS', (tester) async {
      final (m, saved) = await pump(tester);
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Deux');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(m.cues[1].text, 'Deux');
      await tester.tap(find.byTooltip('Save as'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as ASS'));
      await tester.pumpAndSettle();
      expect(saved.single.$1, 'Film.ass');
      expect(utf8.decode(saved.single.$2.sublist(3)), contains('Deux'));
      expect(find.text('Saved to /subs/Film.ass'), findsOneWidget);
      expect(m.dirty, isFalse);
    });

    testWidgets('SUB-030 "now" uses the player position; split here', (
      tester,
    ) async {
      final (m, _) = await pump(tester, position: () => ms(1500));
      await tester.tap(find.text('Split here'));
      await tester.pumpAndSettle();
      expect(m.cues, hasLength(4));
      expect(m.cues[1].start, ms(1500));
    });

    testWidgets('SUB-030 leaving with unsaved changes asks first', (
      tester,
    ) async {
      final (m, _) = await pump(tester);
      m.shift(ms(100));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(SubtitleEditorScreen), findsOneWidget);
    });
  });
}
