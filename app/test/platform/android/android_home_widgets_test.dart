import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_home_widgets.dart';
import 'package:mediahro/platform/android/gen/widget_api.pigeon.dart';
import 'package:mediahro/platform/media_session.dart';

/// The Dart half of lane C4a's home widget (MUS-012).
final class _FakeWidgets extends HomeWidgetsHostApi {
  final states = <WidgetStateMsg?>[];

  @override
  Future<void> update(WidgetStateMsg? state) async => states.add(state);
}

void main() {
  test('MUS-012 now playing and the play state reach the widget', () async {
    final api = _FakeWidgets();
    final w = AndroidHomeWidgets(api: api);
    final art = Uint8List.fromList(const [1, 2, 3]);
    await w.update(
      NowPlaying(title: 'T', artist: 'A', artwork: art),
      playing: true,
    );
    await w.update(null, playing: false);
    final first = api.states.first!;
    expect([first.title, first.artist, first.playing], ['T', 'A', true]);
    expect(first.artwork, art);
    expect(api.states.last, isNull);
  });
}
