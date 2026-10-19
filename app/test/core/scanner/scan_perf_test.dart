import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/scanner/scan_service.dart';

import 'scanner_test.dart' show addSource, localResolver;

// docs/11 §5: library scan of 10 k files ≤ 10 s desktop (≤ 30 s on the
// 2022 mid-range phone, measured on devices); incremental rescan ≤ 2 s.
const _files = 10000;
const _initialBudget = Duration(seconds: 10);
const _incrementalBudget = Duration(seconds: 2);

void main() {
  late Directory dir;
  late LibraryDatabase db;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('mediahro_perf');
    for (var d = 0; d < 100; d++) {
      final sub = Directory('${dir.path}/Folder $d')..createSync();
      for (var i = 0; i < _files ~/ 100; i++) {
        File('${sub.path}/Episode.S01E${i.toString().padLeft(2, '0')}.mkv')
            .writeAsBytesSync(const [1, 2, 3]);
      }
    }
  });
  tearDownAll(() => dir.delete(recursive: true));

  setUp(() async {
    final dbDir = await Directory.systemTemp.createTemp('mediahro_perf_db');
    db = LibraryDatabase.open(dbDir);
    addTearDown(() async {
      await db.close();
      await dbDir.delete(recursive: true);
    });
  });

  test('LIB-003 10 k files scan within the desktop budget and rescan incrementally within 2 s', () async {
    final sid = await addSource(db, dir.uri);
    final svc = ScanService(db: db, resolver: localResolver());
    final sw = Stopwatch()..start();
    final first = await svc.scan(sid);
    final initial = sw.elapsed;
    expect(first.state, ScanJobState.done, reason: '${first.error}');
    expect(first.result.added, _files);

    sw.reset();
    final second = await svc.scan(sid);
    final incremental = sw.elapsed;
    expect(second.result.added + second.result.updated, 0);

    // Reported in CI logs for the perf trend (docs/11 §5).
    // ignore: avoid_print
    print(
      'LIB-003 perf: initial ${initial.inMilliseconds} ms, '
      'incremental ${incremental.inMilliseconds} ms',
    );
    expect(initial, lessThanOrEqualTo(_initialBudget));
    expect(incremental, lessThanOrEqualTo(_incrementalBudget));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
