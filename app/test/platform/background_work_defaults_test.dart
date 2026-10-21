import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/platform_facades.dart';

void main() {
  test('POD-002 background work defaults to foreground only', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final work = c.read(backgroundWorkProvider);
    expect(work, isA<UnsupportedBackgroundWork>());
    expect(await work.available, isFalse);
    expect(await work.runs.isEmpty, isTrue);
  });

  test('POD-002 unsupported scheduling is a no-op', () async {
    const work = UnsupportedBackgroundWork();
    await work.schedulePeriodic(
      'podcast.refresh',
      const Duration(hours: 1),
      unmeteredOnly: true,
    );
    await work.complete('podcast.refresh', success: true);
    await work.cancel('podcast.refresh');
    expect(await work.available, isFalse);
  });
}
