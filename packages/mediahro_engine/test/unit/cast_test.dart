import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/subtitle_convert.dart';

void main() {
  group('CAST-005 passthrough / remux / transcode decision', () {
    test('CAST-005 MP4 H.264/AAC passes through to Chromecast', () {
      final plan = decideCastPlan(
        const MediaProbe(
          container: CastContainer.mp4,
          videoCodec: 'h264',
          height: 1080,
          fps: 24,
          audioCodec: 'aac',
          audioChannels: 2,
        ),
        CastReceiver.chromecast,
      );
      expect(plan.kind, CastPlanKind.passthrough);
    });

    test('CAST-005 MKV with compatible codecs is remuxed', () {
      final plan = decideCastPlan(
        const MediaProbe(
          container: CastContainer.mkv,
          videoCodec: 'h264',
          height: 720,
          audioCodec: 'aac',
        ),
        CastReceiver.chromecast,
      );
      expect(plan.kind, CastPlanKind.remux);
      expect(plan.container, CastContainer.mp4);
      expect(plan.video, StreamAction.copy);
      expect(plan.reasons, ['container mkv']);
    });

    test('CAST-005 HEVC 4K HDR is transcoded for a 1080p receiver', () {
      final plan = decideCastPlan(
        const MediaProbe(
          container: CastContainer.mkv,
          videoCodec: 'hevc',
          height: 2160,
          tenBit: true,
          hdr: true,
          audioCodec: 'truehd',
          audioChannels: 8,
        ),
        CastReceiver.chromecast,
      );
      expect(plan.kind, CastPlanKind.transcode);
      expect(plan.container, CastContainer.hls);
      expect(plan.video, StreamAction.encode);
      expect(plan.audio, StreamAction.encode);
      expect(
        plan.reasons,
        containsAll([
          'video codec hevc',
          'resolution 2160p',
          '10-bit video',
          'HDR video',
          'audio codec truehd',
          '8 audio channels',
        ]),
      );
    });

    test('CAST-005 the same file passes through to a 4K HDR receiver', () {
      final plan = decideCastPlan(
        const MediaProbe(
          container: CastContainer.mp4,
          videoCodec: 'hevc',
          height: 2160,
          tenBit: true,
          hdr: true,
          audioCodec: 'eac3',
          audioChannels: 6,
        ),
        CastReceiver.chromecast4k,
      );
      expect(plan.kind, CastPlanKind.passthrough);
    });

    test('CAST-005 audio-only incompatibility re-encodes only audio', () {
      final plan = decideCastPlan(
        const MediaProbe(
          container: CastContainer.mp4,
          videoCodec: 'h264',
          height: 1080,
          audioCodec: 'dts',
          audioChannels: 6,
        ),
        CastReceiver.airplay,
      );
      expect(plan.kind, CastPlanKind.transcode);
      expect(plan.video, StreamAction.copy);
      expect(plan.audio, StreamAction.encode);
    });

    test('CAST-005 DLNA renderers get MPEG-TS when transcoding', () {
      final plan = decideCastPlan(
        const MediaProbe(container: CastContainer.mkv, videoCodec: 'av1'),
        CastReceiver.dlna,
      );
      expect(plan.container, CastContainer.mpegts);
    });

    test('CAST-005 containers map from mpv file-format names', () {
      expect(MediaProbe.containerOf('matroska,webm'), CastContainer.mkv);
      expect(
        MediaProbe.containerOf('mov,mp4,m4a,3gp,3g2,mj2'),
        CastContainer.mp4,
      );
      expect(MediaProbe.containerOf('mpegts'), CastContainer.mpegts);
      expect(MediaProbe.containerOf('avi'), CastContainer.other);
    });

    test('CAST-005 OS H.264 encoders first; never x264/openh264', () {
      for (final p in EnginePlatform.values) {
        final encoders = castVideoEncoders(p);
        expect(encoders.first, startsWith('h264_'));
        expect(encoders, isNot(contains('libx264')));
        expect(encoders, isNot(contains('libopenh264')));
      }
    });
  });

  group('CAST-005 WebVTT', () {
    test('CAST-005 SRT converts to WebVTT with escaped text', () {
      final vtt = toWebVtt(
        parseSrt(
          '1\n00:00:01,000 --> 00:00:02,500\n<i>Tom & Jerry</i>\n\n'
          '2\n00:01:00,250 --> 00:01:01,000\nLine one\nLine two\n',
        ),
      );
      expect(
        vtt,
        'WEBVTT\n\n'
        '00:00:01.000 --> 00:00:02.500\nTom &amp; Jerry\n\n'
        '00:01:00.250 --> 00:01:01.000\nLine one\nLine two\n\n',
      );
    });

    test('CAST-005 ASS override tags are stripped', () {
      expect(assToPlain(r'{\an8}Top {\b1}bold{\b0}\Nline'), 'Top bold\nline');
    });

    test('SUB-010 TTML, LRC, TXT and MicroDVD convert to cues', () {
      expect(
        parseTtml(
          '<tt ttp:frameRate="25"><p begin="00:00:01:12" dur="2s">A<br/>B</p></tt>',
        ).single.text,
        'A\nB',
      );
      final lrc = parseLrc('[offset:+500]\n[00:01.00]one\n[00:03.00]two\n');
      expect(lrc.first.start, const Duration(milliseconds: 500));
      expect(lrc.first.end, const Duration(milliseconds: 2500));
      expect(
        parseTimestampText('00:00:05 Hello|World').single.text,
        'Hello\nWorld',
      );
      final dvd = parseMicroDvd('{1}{1}25\n{25}{50}Hi|there\n');
      expect(dvd.single.start, const Duration(seconds: 1));
      expect(dvd.single.text, 'Hi\nthere');
    });
  });
}
