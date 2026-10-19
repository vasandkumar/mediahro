import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/search/library_search.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Lane B2 speed budgets (docs/11 §5, ADR-020), run by CI's perf jobs under
/// `flutter drive --profile` with `test_driver/perf_driver.dart`; the numbers
/// land in `binding.reportData`. Budgets are asserted only in profile and
/// release builds; debug runs (the integration jobs) just report them.
/// Mobile budgets are measured on the reference devices (device lab).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object>{
    'platform': Platform.operatingSystem,
    'mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
  };
  tearDownAll(() => binding.reportData = report);

  final mobile = Platform.isAndroid || Platform.isIOS;

  late Directory media;
  late Directory dbDir;
  late LibraryDatabase db;

  setUp(() async {
    media = await Directory.systemTemp.createTemp('mediahro_b2_perf');
    dbDir = await Directory.systemTemp.createTemp('mediahro_b2_perf_db');
    db = LibraryDatabase.open(dbDir);
  });
  tearDown(() async {
    await db.close();
    await media.delete(recursive: true);
    await dbDir.delete(recursive: true);
  });

  Future<int> addLocal() => db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(
          kind: SourceKind.local,
          name: 'Device',
          rootUri: media.uri.toString(),
          addedAt: DateTime.now().toUtc(),
        ),
      );

  testWidgets(
    'LIB-003 10 k files: initial scan ≤ 10 s desktop / 30 s mobile, rescan ≤ 2 s',
    (tester) async {
      for (var d = 0; d < 100; d++) {
        final sub = Directory('${media.path}/Folder $d')..createSync();
        for (var i = 0; i < 100; i++) {
          File('${sub.path}/Episode.S01E${i.toString().padLeft(2, '0')}.mkv')
              .writeAsBytesSync(const [1, 2, 3]);
        }
      }
      final sid = await addLocal();
      final svc = ScanService(
        db: db,
        resolver: DefaultSourceResolver(
          builders: {SourceKind.local: (_) => const LocalFileSystem()},
        ),
      );
      final sw = Stopwatch()..start();
      final first = await svc.scan(sid);
      final initial = sw.elapsed;
      expect(first.state, ScanJobState.done, reason: '${first.error}');
      expect(first.result.added, 10000);
      sw.reset();
      final second = await svc.scan(sid);
      final incremental = sw.elapsed;
      expect(second.result.added + second.result.updated, 0);
      report['lib003_initial_ms'] = initial.inMilliseconds;
      report['lib003_incremental_ms'] = incremental.inMilliseconds;
      debugPrint(
        'LIB-003 perf: initial ${initial.inMilliseconds} ms, '
        'incremental ${incremental.inMilliseconds} ms',
      );
      if (!kDebugMode) {
        expect(initial, lessThanOrEqualTo(Duration(seconds: mobile ? 30 : 10)));
        expect(incremental, lessThanOrEqualTo(const Duration(seconds: 2)));
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'LIB-005 search over 50 k items: median ≤ 30 ms desktop / 50 ms mobile',
    (tester) async {
      final sid = await addLocal();
      const words = [
        'alpha',
        'bravo',
        'charlie',
        'delta',
        'echo',
        'foxtrot',
        'golf',
        'hotel',
      ];
      final now = DateTime.utc(2026);
      await db.batch((b) {
        b.insertAll(db.items, [
          for (var i = 0; i < 50000; i++)
            ItemsCompanion.insert(
              sourceId: sid,
              relPath: 'd${i ~/ 500}/file_$i.mkv',
              parentPath: 'd${i ~/ 500}',
              name: 'file_$i.mkv',
              ext: 'mkv',
              kind: ItemKind.video,
              size: i,
              mtime: now,
              addedAt: now,
              scannedAt: now,
              title: '${words[i % 8]} ${words[(i ~/ 8) % 8]} $i',
              sortTitle: '${words[i % 8]} $i',
              height: Value(i.isEven ? 1080 : 2160),
            ),
        ]);
      });
      await IndexWriter(db).rebuildFts();
      final search = LibrarySearch(db);
      await search.search(const SearchRequest('alp'));
      final times = <int>[];
      for (var i = 0; i < 21; i++) {
        final sw = Stopwatch()..start();
        final r = await search.search(
          SearchRequest(
            i.isEven ? 'char del' : 'ho',
            filters: const SearchFilters(resolutions: {ResolutionClass.uhd}),
          ),
        );
        times.add(sw.elapsedMicroseconds);
        expect(r, isNotEmpty);
      }
      times.sort();
      final median = Duration(microseconds: times[10]);
      report['lib005_median_us'] = median.inMicroseconds;
      report['lib005_p95_us'] = times[19];
      debugPrint(
        'LIB-005 perf: median ${median.inMicroseconds} µs over 50 k items',
      );
      if (!kDebugMode) {
        expect(
          median,
          lessThanOrEqualTo(Duration(milliseconds: mobile ? 50 : 30)),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
