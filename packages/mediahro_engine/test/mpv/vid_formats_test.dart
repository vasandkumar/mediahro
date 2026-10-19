@Tags(['ffi'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/mpv_options.dart';

import 'support.dart';

/// VID-001 containers, VID-002 video codecs, VID-003 audio codecs in video:
/// every generated corpus file opens, reports the expected tracks and codecs,
/// renders a first frame and plays.
void main() {
  final skip = ffiSkipReason;

  Future<void> check(CorpusItem item) async {
    final e = headlessEngine();
    addTearDown(e.dispose);
    await e.open(UriSource(item.uri));
    final s = await waitFor(
      e,
      (s) =>
          s.status == PlaybackStatus.error ||
          s.status == PlaybackStatus.ended ||
          (s.status == PlaybackStatus.playing && s.position > Duration.zero),
      reason: '$item playing',
    );
    expect(s.error, isNull, reason: '$item: ${s.error}');
    int count(TrackType t) => s.tracks.where((x) => x.type == t).length;
    final x = item.expect;
    if (x['video'] case final int v) {
      expect(count(TrackType.video), v, reason: '$item video tracks');
    }
    if (x['audio'] case final int a) {
      expect(count(TrackType.audio), a, reason: '$item audio tracks');
    }
    if (x['sub'] case final int n) {
      expect(count(TrackType.subtitle), n, reason: '$item subtitle tracks');
    }
    if (x['videoCodec'] case final String c) {
      expect(
        s.tracks.firstWhere((t) => t.type == TrackType.video).codec,
        c,
        reason: '$item video codec',
      );
    }
    if (x['audioCodec'] case final String c) {
      expect(
        s.tracks.firstWhere((t) => t.type == TrackType.audio).codec,
        c,
        reason: '$item audio codec',
      );
    }
    if (x['audioCodecs'] case final List<Object?> cs) {
      expect(
        s.tracks.where((t) => t.type == TrackType.audio).map((t) => t.codec),
        cs,
        reason: '$item audio codecs',
      );
    }
    if (x['chapters'] case final int n) {
      expect(s.chapters, hasLength(n), reason: '$item chapters');
    }
    if (x['width'] case final int w) {
      final v = s.tracks.firstWhere((t) => t.type == TrackType.video);
      expect((v.width, v.height), (w, x['height']), reason: '$item size');
    }
    if ((x['video'] as int? ?? 0) > 0) {
      final first = await e.softwareRenderer!.firstFrame.timeout(
        const Duration(seconds: 10),
      );
      expect(first, isNotNull, reason: '$item first frame');
    }
  }

  group('VID-001 containers', () {
    for (final item in corpusItems(category: 'containers')) {
      test('VID-001 ${item.file} opens with expected tracks', () async {
        await check(item);
      }, skip: skip);
    }
    for (final item in corpusItems(category: 'playlists')) {
      test('VID-001 playlist ${item.file} expands', () async {
        final e = headlessEngine();
        addTearDown(e.dispose);
        await e.open(UriSource(item.uri));
        await waitFor(
          e,
          (s) => s.status == PlaybackStatus.playing,
          reason: 'playlist playing',
        );
        final count = await prop(e, 'playlist-count');
        expect(count, item.expect['playlistEntries']);
      }, skip: skip);
    }
  });

  group('VID-002 video codecs', () {
    for (final item in corpusItems(id: 'VID-002')) {
      test('VID-002 ${item.file} decodes', () async {
        await check(item);
      }, skip: skip);
    }
    test('VID-002 hardware decode is requested first (auto-safe)', () async {
      final e = headlessEngine();
      addTearDown(e.dispose);
      await e.open(UriSource(corpusFile('mkv_multitrack.mkv').uri));
      // Software renderer runs have hwdec off; on-screen modes use auto-safe.
      for (final mode in [
        VideoOutputMode.renderApi,
        VideoOutputMode.androidSurface,
      ]) {
        expect(
          defaultMpvOptions(
            platform: EnginePlatform.current,
            role: EngineRole.video,
            video: mode,
          )['hwdec'],
          'auto-safe',
        );
      }
      final s = await waitFor(e, (s) => s.video.videoCodec != null);
      expect(s.video.hwdec, HwdecPath.none, reason: 'software renderer');
    }, skip: skip);
  });

  group('VID-003 audio codecs in video', () {
    for (final item in corpusItems(id: 'VID-003')) {
      test('VID-003 ${item.file} decodes audio', () async {
        await check(item);
      }, skip: skip);
    }
  });
}
