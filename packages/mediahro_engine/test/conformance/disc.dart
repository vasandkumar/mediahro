import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import 'support.dart';

/// VID-007: unencrypted VIDEO_TS and BDMV folders with menu-less title
/// selection, chapters and stream languages, without GPL code.
void discSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();

  for (final item in corpusItems(category: 'disc')) {
    group('VID-007 ${item.expect['disc']} folder', () {
      Future<DiscInfo> read() async {
        final info = await DiscReader.read(Directory(corpusPath(item.file)));
        expect(info, isNotNull);
        return info!;
      }

      test(
        'VID-007 ${item.file} lists titles, chapters and languages',
        () async {
          final info = await read();
          expect(info.kind.name, item.expect['disc']);
          expect(info.encrypted, isFalse);
          expect(info.titles, hasLength(item.expect['titles']));
          final main = info.mainTitle!;
          expect(main.chapters, hasLength(item.expect['chapters']));
          expect(main.duration.inSeconds, inInclusiveRange(5, 6));
          expect(main.audio.first.language, item.expect['audioLang']);
          if (item.expect['subLang'] case final String lang) {
            expect(main.subtitles.first.language, lang);
          }
        },
        skip: skip,
      );

      test('VID-007 ${item.file} main title plays with its chapters', () async {
        final info = await read();
        final title = info.mainTitle!;
        final e = headlessEngine();
        addTearDown(e.dispose);
        await e.open(title.source, opts: title.openOptions());
        final s = await waitPlaying(e, reason: 'disc title playing');
        expect(s.error, isNull);
        expect(s.tracks.where((t) => t.type == TrackType.video), hasLength(1));
        expect(s.chapters, hasLength(title.chapters.length));
        await e.seek(title.chapters.last.start, mode: SeekMode.exact);
        final after = await waitFor(
          e,
          (s) => s.position >= title.chapters.last.start,
          reason: 'seek to last chapter',
        );
        expect(after.error, isNull);
      }, skip: skip);

      test('VID-007 ${item.file} every title is selectable', () async {
        final info = await read();
        for (final title in info.titles) {
          final e = headlessEngine();
          addTearDown(e.dispose);
          await e.open(title.source, opts: title.openOptions());
          final s = await waitPlaying(e, reason: 'title ${title.number}');
          expect(s.error, isNull, reason: 'title ${title.number}');
        }
      }, skip: skip);
    });
  }

  test('VID-007 non-disc folders are not mistaken for discs', () async {
    expect(DiscReader.isDiscFolder(Directory(env.corpusDir)), isFalse);
    expect(await DiscReader.read(Directory(env.corpusDir)), isNull);
  }, skip: skip);
}

/// VID-001 ISO images: the same titles, read from UDF images written by an
/// independent tool (pycdlib) and streamed out of the image.
void discImageSuite() {
  final skip = ffiSkipReason;
  prepareCorpus();
  final images = corpusItems(category: 'disc-image');
  if (images.isEmpty) {
    test(
      'VID-001 ISO images',
      () {},
      skip:
          'no ISO fixtures (pip install pycdlib for tools/corpus/make_iso.py)',
    );
    return;
  }
  for (final item in images) {
    test('VID-001 ${item.file} plays its main title from the image', () async {
      const image = LocalFileSystem();
      final file = await image.open(item.uri);
      addTearDown(file.close);
      final info = await DiscReader.readImage(file);
      expect(info, isNotNull, reason: 'UDF with a disc structure');
      expect(info!.kind.name, item.expect['disc']);
      expect(info.titles, hasLength(item.expect['titles']));
      final title = info.mainTitle!;
      expect(title.chapters, hasLength(item.expect['chapters']));
      final e = headlessEngine();
      addTearDown(e.dispose);
      await e.open(title.source, opts: title.openOptions());
      final s = await waitPlaying(e, reason: 'title from image');
      expect(s.error, isNull);
      expect(s.chapters, hasLength(title.chapters.length));
    }, skip: skip);

    test(
      'VID-001 opening ${item.file} directly plays the main title',
      () async {
        final e = headlessEngine();
        addTearDown(e.dispose);
        await e.open(UriSource(item.uri));
        final s = await waitPlaying(e, reason: 'iso opened directly');
        expect(s.error, isNull);
        expect(s.tracks.where((t) => t.type == TrackType.video), hasLength(1));
        expect(s.chapters, hasLength(item.expect['chapters']));
      },
      skip: skip,
    );
  }
}
