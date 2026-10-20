import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/src/mpv/stall_guard.dart';

/// VID-002: a frozen hardware decoder is detected once per item.
void main() {
  const tick = Duration(milliseconds: 500);

  bool feed(
    StallGuard g,
    int ticks, {
    Duration position = const Duration(seconds: 1),
    bool playing = true,
    bool hardwareVideo = true,
  }) {
    var fired = false;
    for (var i = 0; i < ticks; i++) {
      fired |= g.check(
        elapsed: tick,
        position: position,
        playing: playing,
        hardwareVideo: hardwareVideo,
      );
    }
    return fired;
  }

  test('VID-002 a frozen position while playing triggers once', () {
    final g = StallGuard();
    expect(feed(g, 6), isFalse, reason: '3 s is the threshold');
    expect(feed(g, 1), isTrue);
    expect(feed(g, 20), isFalse, reason: 'once per item');
    g.reset();
    expect(feed(g, 8), isTrue, reason: 'a new item may recover again');
  });

  test('VID-002 progress, pause, buffering and software decode never '
      'trigger', () {
    final g = StallGuard();
    for (var i = 0; i < 20; i++) {
      expect(
        g.check(
          elapsed: tick,
          position: tick * i,
          playing: true,
          hardwareVideo: true,
        ),
        isFalse,
      );
    }
    expect(feed(g, 20, playing: false), isFalse);
    expect(feed(g, 20, hardwareVideo: false), isFalse);
    // Not playing in between restarts the count.
    expect(feed(g, 5), isFalse);
    expect(feed(g, 1, playing: false), isFalse);
    expect(feed(g, 5), isFalse);
  });
}
