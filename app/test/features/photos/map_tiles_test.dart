import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/map/map_tiles.dart';
import 'package:mediahro/features/photos/map/web_mercator.dart';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4, //
]);

void main() {
  late Directory dir;
  var now = DateTime(2026, 10, 21);
  var enabled = true;
  final requested = <Uri>[];
  Future<Uint8List?> Function(Uri) respond = (_) async => _png;

  NetworkMapTileSource make({
    int maxParallel = 6,
    int maxDiskBytes = 1 << 30,
    int trimEvery = 200,
  }) => NetworkMapTileSource(
    directory: dir,
    isEnabled: () => enabled,
    fetch: (uri) {
      requested.add(uri);
      return respond(uri);
    },
    clock: () => now,
    maxParallel: maxParallel,
    maxDiskBytes: maxDiskBytes,
    trimEvery: trimEvery,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('maptiles');
    now = DateTime.now();
    enabled = true;
    requested.clear();
    respond = (_) async => _png;
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('IMG-007 tiles are asked for by their address', () async {
    await make().load(const TileId(10, 518, 352));
    expect(
      requested.single.toString(),
      'https://tiles.mediahro.com/10/518/352.png',
    );
  });

  test('IMG-007 with the switch off nothing leaves the device', () async {
    enabled = false;
    expect(await make().load(const TileId(3, 1, 2)), isNull);
    expect(requested, isEmpty);
  });

  test('IMG-007 tiles already on disk show with the switch off', () async {
    final source = make();
    await source.load(const TileId(3, 1, 2));
    await source.settled();
    enabled = false;
    requested.clear();
    expect(await source.load(const TileId(3, 1, 2)), _png);
    expect(requested, isEmpty);
  });

  test('IMG-007 a tile is fetched once and then read from disk', () async {
    final source = make();
    await source.load(const TileId(5, 4, 3));
    await source.settled();
    final again = make();
    expect(await again.load(const TileId(5, 4, 3)), _png);
    expect(requested, hasLength(1));
  });

  test('IMG-007 two requests for one tile share a fetch', () async {
    final gate = Completer<Uint8List?>();
    respond = (_) => gate.future;
    final source = make();
    final a = source.load(const TileId(2, 1, 1));
    final b = source.load(const TileId(2, 1, 1));
    gate.complete(_png);
    expect(await a, _png);
    expect(await b, _png);
    expect(requested, hasLength(1));
  });

  test('IMG-007 a failed tile is not retried at once', () async {
    respond = (_) async => null;
    final source = make();
    expect(await source.load(const TileId(4, 4, 4)), isNull);
    expect(await source.load(const TileId(4, 4, 4)), isNull);
    expect(requested, hasLength(1));
    now = now.add(const Duration(seconds: 31));
    respond = (_) async => _png;
    expect(await source.load(const TileId(4, 4, 4)), _png);
    expect(requested, hasLength(2));
  });

  test(
    'IMG-007 a network error leaves the tile missing, not the map',
    () async {
      respond = (_) async => throw const SocketException('offline');
      expect(await make().load(const TileId(4, 1, 1)), isNull);
    },
  );

  test('IMG-007 an answer that is not a PNG is refused', () async {
    respond = (_) async => Uint8List.fromList(List.filled(40, 0x3c));
    final source = make();
    expect(await source.load(const TileId(4, 2, 2)), isNull);
    await source.settled();
    expect(File('${dir.path}/4/2/2.png').existsSync(), isFalse);
  });

  test('IMG-007 an old tile is refreshed, and kept when that fails', () async {
    final first = make();
    await first.load(const TileId(6, 2, 2));
    await first.settled();
    now = now.add(const Duration(days: 31));
    respond = (_) async => null;
    requested.clear();
    expect(await make().load(const TileId(6, 2, 2)), _png);
    expect(requested, hasLength(1));
  });

  test('IMG-007 at most maxParallel tiles load at once', () async {
    var running = 0;
    var peak = 0;
    respond = (_) async {
      peak = running = running + 1;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      running--;
      return _png;
    };
    var concurrent = 0;
    respond = (_) async {
      concurrent++;
      if (concurrent > peak) peak = concurrent;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      concurrent--;
      return _png;
    };
    peak = 0;
    final source = make(maxParallel: 3);
    await Future.wait([
      for (var i = 0; i < 12; i++) source.load(TileId(8, i, 0)),
    ]);
    await source.settled();
    expect(requested, hasLength(12));
    expect(peak, 3);
  });

  test('IMG-007 turning the switch off stops queued tiles', () async {
    final gate = Completer<Uint8List?>();
    respond = (_) => gate.future;
    final source = make(maxParallel: 1);
    final first = source.load(const TileId(8, 0, 0));
    final second = source.load(const TileId(8, 1, 0));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    enabled = false;
    gate.complete(_png);
    await first;
    expect(await second, isNull);
    expect(requested, hasLength(1));
  });

  test('IMG-007 the disk cache stays under its size', () async {
    final source = make(maxDiskBytes: 60, trimEvery: 5);
    for (var i = 0; i < 10; i++) {
      await source.load(TileId(9, i, 0));
      await source.settled();
    }
    final left = dir
        .listSync(recursive: true)
        .whereType<File>()
        .fold<int>(0, (a, f) => a + f.lengthSync());
    expect(left, lessThanOrEqualTo(60));
  });

  test('IMG-007 clearing removes every tile', () async {
    final source = make();
    await source.load(const TileId(1, 0, 0));
    await source.settled();
    await source.clear();
    expect(dir.existsSync(), isFalse);
  });
}
