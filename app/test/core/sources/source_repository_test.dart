import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/scanner/probe_queue.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/source_builders.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../fakes.dart';
import '../seed.dart';

final class _Prober implements MediaProber {
  final order = <int>[];
  final gate = Completer<void>();

  @override
  Future<ProbeResult> probe(VirtualFile file, ItemRow item) async {
    order.add(item.id);
    if (order.length == 1) await gate.future;
    return ProbeResult(
      durationMs: 1000 * item.id,
      width: 1920,
      height: 1080,
      videoCodec: 'hevc',
    );
  }
}

void main() {
  late LibraryDatabase db;
  setUp(() => db = LibraryDatabase.memory());
  tearDown(() => db.close());

  test('LIB-002/PRIV-006 add tests the connection; credentials live only in secure storage', () async {
    final dir = await Directory.systemTemp.createTemp('mediahro_src');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/a.mkv').writeAsStringSync('x');
    final secrets = FakeSecureStorage();
    final resolver = DefaultSourceResolver(
      builders: defaultFileSystemBuilders(),
      secureStorage: secrets,
    );
    final repo = SourceRepository(
      db: db,
      resolver: resolver,
      secureStorage: secrets,
    );
    final s = NewSource(
      kind: SourceKind.local,
      name: 'Films',
      root: dir.uri,
      credential: const StoredCredential(userName: 'u', secret: 'hunter2'),
    );
    expect(await repo.test(s), 1);
    final id = await repo.add(s);
    final row = await (db.select(
      db.sources,
    )..where((x) => x.id.equals(id))).getSingle();
    expect(row.credentialKey, startsWith('source.'));
    expect(row.toString(), isNot(contains('hunter2')));
    expect(secrets.values[row.credentialKey], contains('hunter2'));
    final access = await resolver.resolve(row);
    expect((access.spec.userName, access.spec.secret), ('u', 'hunter2'));

    await ScanService(db: db, resolver: resolver, useIsolates: false).scan(id);
    final sum = (await repo.summaries()).single;
    expect((sum.items, sum.health), (1, SourceHealth.ok));

    await repo.remove(id);
    expect(secrets.values, isEmpty);
    expect(await db.select(db.items).get(), isEmpty);
  });

  test('LIB-002 an unreachable root fails the test with a typed error', () async {
    final repo = SourceRepository(
      db: db,
      resolver: DefaultSourceResolver(builders: defaultFileSystemBuilders()),
    );
    await expectLater(
      repo.test(
        NewSource(
          kind: SourceKind.local,
          name: 'x',
          root: Uri.directory(
            '${Directory.systemTemp.path}/nope-${DateTime.now().microsecondsSinceEpoch}',
          ),
        ),
      ),
      throwsA(isA<VirtualFileException>()),
    );
  });

  test('NET-001 builders create SMB/NFS/FTP/SFTP/WebDAV/DLNA file systems from source specs', () {
    final b = defaultFileSystemBuilders();
    SourceSpec spec(
      SourceKind k,
      String root, [
      Map<String, String> o = const {},
    ]) => SourceSpec(
      kind: k,
      root: Uri.parse(root),
      options: o,
      userName: 'u',
      secret: 'p',
    );
    expect(
      b[SourceKind.smb]!(
        spec(SourceKind.smb, 'smb://nas/media/', {
          'encrypt': 'true',
          'version': 'smb3',
        }),
      ).schemes,
      {'smb'},
    );
    expect(
      b[SourceKind.nfs]!(spec(SourceKind.nfs, 'nfs://nas/export/')).schemes,
      {'nfs'},
    );
    expect(
      b[SourceKind.sftp]!(spec(SourceKind.sftp, 'sftp://host:2222/srv/'))
          .schemes,
      contains('sftp'),
    );
    expect(
      b[SourceKind.webdav]!(spec(SourceKind.webdav, 'davs://cloud/dav/'))
          .schemes,
      contains('davs'),
    );
    expect(
      b[SourceKind.dlna]!(
        spec(SourceKind.dlna, 'dlna://uuid/', {
          'controlUrl': 'http://10.0.0.2:8200/ctl/ContentDir',
        }),
      ).schemes,
      {'dlna'},
    );
    final policy = SourceOnlyPolicy(['NAS.local']);
    expect(policy.isUserConfiguredHost('nas.local'), isTrue);
    expect(policy.isUserConfiguredHost('api.themoviedb.org'), isFalse);
  });

  test('LIB-003 probe queue: visible items first, facts and hashes land in the index', () async {
    final seed = Seed(db);
    final ids = [for (var i = 0; i < 6; i++) await seed.item('v$i.mkv')];
    final prober = _Prober();
    final q = ProbeQueue(
      db: db,
      opener: (item) async => MemoryFile(
        Uri.parse('mem:///${item.relPath}'),
        Uint8List.fromList([item.id]),
      ),
      prober: prober,
      concurrency: 1,
    )..enqueue(ids);
    // The first item is in flight; the user scrolls to the last two.
    await Future<void>.delayed(Duration.zero);
    q.prioritize({ids[5], ids[4]});
    prober.gate.complete();
    await q.idle();
    expect(prober.order.first, ids[0]);
    expect(prober.order.sublist(1, 3).toSet(), {ids[4], ids[5]});
    final rows = await db.select(db.items).get();
    expect(
      rows.every(
        (r) => r.probed && r.contentHash != null && r.videoCodec == 'hevc',
      ),
      isTrue,
    );
    expect(q.pending, 0);
    await q.dispose();
  });
}
