import 'package:mediahro_subtitles/mediahro_subtitles.dart';
import 'package:test/test.dart';

void main() {
  test('SUB-010 sidecar extensions map to formats', () {
    expect(subtitleFormatForExtension('.SRT'), SubtitleFormat.srt);
    expect(subtitleFormatForExtension('vtt'), SubtitleFormat.webvtt);
    expect(subtitleFormatForExtension('ass'), SubtitleFormat.ass);
    expect(subtitleFormatForExtension('sup'), SubtitleFormat.pgs);
    expect(subtitleFormatForExtension('mkv'), isNull);
  });

  test('PRIV-005 default parse limits are bounded', () {
    const l = ParseLimits();
    expect(l.maxBytes, lessThanOrEqualTo(20 * 1024 * 1024));
    expect(l.timeout, lessThanOrEqualTo(const Duration(seconds: 10)));
  });
}
