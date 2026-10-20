import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/sources/connection_health.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../fakes.dart';

final class _Flaky implements VirtualFile {
  _Flaky(this.uri, this.bytes, {this.failAt});

  @override
  final Uri uri;
  final Uint8List bytes;
  int? failAt;
  final reads = <int>[];

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    reads.add(offset);
    final f = failAt;
    if (f != null && offset >= f) {
      failAt = null;
      throw VirtualFileException(
        VirtualFileError.unreachable,
        uri,
        'link dropped',
      );
    }
    if (offset >= bytes.length) return Uint8List(0);
    return Uint8List.sublistView(
      bytes,
      offset,
      (offset + length).clamp(0, bytes.length),
    );
  }

  @override
  Future<void> close() async {}
}

final class _Metered implements NetworkStatusFacade {
  static const _state = NetworkState(
    transport: NetworkTransport.cellular,
    metered: true,
  );

  @override
  Future<NetworkState> current() async => _state;

  @override
  Stream<NetworkState> changes() => const Stream.empty();
}

void main() {
  late LibraryDatabase db;
  late Directory dir;
  final data = Uint8List.fromList(List.generate(300000, (i) => i % 251));

  setUp(() async {
    db = LibraryDatabase.memory();
    dir = await Directory.systemTemp.createTemp('mediahro_dl');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<DownloadRow> waitFor(
    DownloadManager m,
    int id,
    DownloadState s,
  ) async {
    for (var i = 0; i < 400; i++) {
      final d = (await m.all()).firstWhere((x) => x.id == id);
      if (d.state == s) return d;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('download $id never reached $s');
  }

  test(
    'NET-018 downloads resume after a dropped connection and play offline',
    () async {
      final remote = Uri.parse('smb://nas/share/Films/Movie.mkv');
      final src = _Flaky(remote, data, failAt: 128 * 1024);
      final m = DownloadManager(
        db: db,
        directory: dir,
        opener: (_) async => src,
        chunk: 64 * 1024,
      );
      addTearDown(m.dispose);
      final id = await m.enqueue(remote, title: 'Movie');
      await waitFor(m, id, DownloadState.failed);
      expect(
        File('${(await m.all()).single.localPath}.part').lengthSync(),
        128 * 1024,
      );
      await m.resume(id);
      final done = await waitFor(m, id, DownloadState.done);
      expect(
        src.reads.where((o) => o == 0),
        hasLength(1),
        reason: 'resumed, not restarted',
      );
      expect(File(done.localPath).readAsBytesSync(), data);
      expect((await m.localFor(remote))!.path, done.localPath);
    },
  );

  test('NET-018 size quota, expiry sweep, pause and removal', () async {
    var now = DateTime.utc(2026, 10, 19);
    final m = DownloadManager(
      db: db,
      directory: dir,
      opener: (u) async => MemoryFile(u, data),
      quotaBytes: 500000,
      clock: () => now,
    );
    addTearDown(m.dispose);
    final a = await m.enqueue(
      Uri.parse('dav://h/a.mkv'),
      title: 'A',
      knownSize: data.length,
      keepFor: const Duration(days: 7),
    );
    await waitFor(m, a, DownloadState.done);
    expect(
      () =>
          m.enqueue(Uri.parse('dav://h/b.mkv'), title: 'B', knownSize: 300000),
      throwsA(isA<QuotaExceeded>()),
    );
    now = now.add(const Duration(days: 8));
    expect(await m.sweepExpired(), 1);
    expect(await m.localFor(Uri.parse('dav://h/a.mkv')), isNull);
    final b = await m.enqueue(
      Uri.parse('dav://h/b.mkv'),
      title: 'B',
      knownSize: 300000,
    );
    await waitFor(m, b, DownloadState.done);
    await m.remove(b);
    expect(await m.all(), hasLength(1));
    expect(dir.listSync().whereType<File>(), isEmpty);
  });

  test('NET-019 latency and throughput test with cache suggestion and metered warning', () async {
    final fs = MemoryFileSystem({
      'Films/big.mkv': Uint8List(4 << 20),
      'Films/small.srt': Uint8List(10),
    });
    final r = await ConnectionHealth(
      network: _Metered(),
    ).test(fs, MemoryFileSystem.root.resolve('Films/'), sampleBytes: 2 << 20);
    expect(r.sampledBytes, 2 << 20);
    expect(r.throughputMbps, greaterThan(0));
    expect(r.warnings, contains(HealthWarning.metered));
    expect(r.suggestedCacheMiB, inInclusiveRange(64, 1024));
    expect(ConnectionHealth.suggestCache(20, Duration.zero), (450, 90));
    expect(ConnectionHealth.suggestCache(500, Duration.zero), (64, 10));
    expect(
      ConnectionHealth.suggestCache(500, const Duration(milliseconds: 200)).$2,
      30,
    );
  });
}
