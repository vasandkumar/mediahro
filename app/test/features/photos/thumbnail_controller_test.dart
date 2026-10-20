import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';

PhotoEntry entry(int id) => PhotoEntry(
  id: id,
  sourceId: 1,
  relPath: '$id.jpg',
  name: '$id.jpg',
  ext: 'jpg',
  isVideo: false,
  size: 10,
  mtime: DateTime(2026),
  date: DateTime(2026),
);

final class FakeSource implements ThumbnailSource {
  final Map<int, Completer<File>> waiting = {};
  final List<(int, ThumbnailPriority)> loads = [];
  final List<(int, ThumbnailPriority)> bumps = [];
  final List<int> cancelled = [];

  @override
  Future<File> load(
    PhotoEntry entry,
    ThumbnailPriority priority,
    void Function(JobHandle) onQueued,
  ) {
    loads.add((entry.id, priority));
    return (waiting[entry.id] = Completer<File>()).future;
  }

  @override
  void reprioritise(int entryId, ThumbnailPriority priority) =>
      bumps.add((entryId, priority));

  @override
  void cancel(int entryId) {
    cancelled.add(entryId);
    waiting[entryId]?.completeError(const JobCancelled());
  }
}

void main() {
  late FakeSource src;
  late ThumbnailController c;

  setUp(() {
    src = FakeSource();
    c = ThumbnailController(src);
  });

  tearDown(() => c.dispose());

  test(
    'IMG-003 before the viewport is known every request is visible priority',
    () {
      unawaited(c.request(entry(1), 0));
      expect(src.loads.single, (1, ThumbnailPriority.visible));
    },
  );

  test('IMG-003 requests are prioritised by distance from the viewport', () {
    c.viewport(100, 120, screenItems: 20);
    for (final i in [110, 90, 150, 300]) {
      unawaited(c.request(entry(i), i));
    }
    expect(src.loads, [
      (110, ThumbnailPriority.visible),
      (90, ThumbnailPriority.nearby),
      (150, ThumbnailPriority.prefetch),
      (300, ThumbnailPriority.prefetch),
    ]);
  });

  test('IMG-003 a second request for the same entry joins the first', () async {
    final a = c.request(entry(1), 0);
    final b = c.request(entry(1), 0);
    expect(src.loads, hasLength(1));
    src.waiting[1]!.complete(File('/t/1.webp'));
    expect((await a)?.path, (await b)?.path);
  });

  test(
    'IMG-003 resolved files are served without asking the source again',
    () async {
      final f = c.request(entry(1), 0);
      src.waiting[1]!.complete(File('/t/1.webp'));
      await f;
      expect(c.resolved(1)?.path, '/t/1.webp');
      expect((await c.request(entry(1), 0))?.path, '/t/1.webp');
      expect(src.loads, hasLength(1));
    },
  );

  test('IMG-003 moving the viewport re-prioritises pending tiles and drops far ones', () {
    c.viewport(0, 20, screenItems: 20);
    for (final i in [5, 50, 400]) {
      unawaited(c.request(entry(i), i));
    }
    src.bumps.clear();
    c.viewport(40, 60, screenItems: 20);
    expect(src.bumps, contains((50, ThumbnailPriority.visible)));
    expect(src.bumps, contains((5, ThumbnailPriority.prefetch)));
    expect(src.cancelled, [400], reason: 'more than 3 screens away');
  });

  test('IMG-003 releasing a tile cancels its queued job', () async {
    final f = c.request(entry(7), 7);
    c.release(7);
    expect(src.cancelled, [7]);
    expect(await f, isNull, reason: 'a cancelled request resolves to nothing');
    expect(c.failed(7), isFalse, reason: 'cancelling is not failing');
  });

  test('IMG-003 a failed load is remembered until retried', () async {
    final f = c.request(entry(3), 3);
    src.waiting[3]!.completeError(StateError('unreadable'));
    expect(await f, isNull);
    expect(c.failed(3), isTrue);
    c.retry(3);
    expect(c.failed(3), isFalse);
    unawaited(c.request(entry(3), 3));
    expect(src.loads.where((l) => l.$1 == 3), hasLength(2));
  });

  test(
    'IMG-003 memory is bounded: the least recently used file is forgotten',
    () async {
      final small = ThumbnailController(src, memory: 2);
      addTearDown(small.dispose);
      for (final id in [1, 2, 3]) {
        final f = small.request(entry(id), id);
        src.waiting[id]!.complete(File('/t/$id.webp'));
        await f;
      }
      expect(small.resolved(1), isNull);
      expect(small.resolved(2), isNotNull);
      expect(small.resolved(3), isNotNull);
    },
  );
}
