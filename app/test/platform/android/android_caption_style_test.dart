import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_caption_style.dart';
import 'package:mediahro/platform/android/gen/caption_api.pigeon.dart';
import 'package:mediahro/platform/caption_style.dart';

/// The Dart half of lane C4a's caption style (ADR-030).
final class _FakeCaptions extends CaptionStyleHostApi {
  _FakeCaptions(this.style);
  final CaptionStyleMsg? style;

  @override
  Future<CaptionStyleMsg?> current() async => style;
}

CaptionStyleMsg _msg({CaptionEdgeMsg edge = CaptionEdgeMsg.outline}) =>
    CaptionStyleMsg(
      enabled: true,
      fontFamily: 'sans-serif-condensed',
      scale: 1.5,
      foregroundArgb: 0xFFFFFF00,
      edge: edge,
      edgeArgb: 0xFF000000,
    );

void main() {
  test('SUB-014 system caption settings map through', () async {
    final s = (await AndroidCaptionStyle(
      api: _FakeCaptions(_msg()),
      events: Stream.empty,
    ).current())!;
    expect(s.enabled, isTrue);
    expect(s.fontFamily, 'sans-serif-condensed');
    expect(s.scale, 1.5);
    expect(s.foregroundArgb, 0xFFFFFF00);
    expect(s.backgroundArgb, isNull, reason: 'not set by the user');
    expect(s.edge, CaptionEdge.outline);
    expect(s.edgeArgb, 0xFF000000);
  });

  test('SUB-014 no caption service is null', () async {
    expect(
      await AndroidCaptionStyle(
        api: _FakeCaptions(null),
        events: Stream.empty,
      ).current(),
      isNull,
    );
  });

  test('SUB-014 changes stream maps every edge type', () async {
    final events = StreamController<CaptionStyleMsg>();
    final captions = AndroidCaptionStyle(
      api: _FakeCaptions(null),
      events: () => events.stream,
    );
    final got = <CaptionEdge>[];
    final sub = captions.changes.listen((s) => got.add(s.edge));
    for (final e in CaptionEdgeMsg.values) {
      events.add(_msg(edge: e));
    }
    await pumpEventQueue();
    await sub.cancel();
    expect(got, CaptionEdge.values);
  });
}
