import 'adr027.dart';
import 'adr031.dart';
import 'adr032.dart';
import 'api_additions.dart';
import 'audio.dart';
import 'cast.dart';
import 'disc.dart';
import 'subtitles.dart';
import 'vid_formats.dart';
import 'vid_hdr.dart';
import 'vid_playback.dart';

/// Every engine conformance suite, in feature-ID order. Run by
/// `test/engine_conformance_test.dart` on desktop and by the example app's
/// integration tests on Android, iOS, macOS and Windows.
void runConformanceSuites() {
  vidFormatsSuite();
  vidPlaybackSuite();
  discSuite();
  discImageSuite();
  vidHdrSuite();
  subtitlesSuite();
  audioSuite();
  castSuite();
  apiAdditionsSuite();
  adr027Suite();
  adr031Suite();
  adr032Suite();
}
