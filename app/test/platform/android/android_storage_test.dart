import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_storage.dart';
import 'package:mediahro/platform/android/gen/storage_api.pigeon.dart';
import 'package:mediahro/platform/storage.dart';

/// The Dart half of lane C4a's StorageFacade: paging, chunked saves,
/// change filtering and error mapping over a fake Pigeon host API.
final class _FakeApi extends StorageHostApi {
  final List<MediaStoreEntryMsg> media = [];
  final List<Object> writes = [];
  final List<String> watched = [];
  PlatformException? failWith;
  String? saveTarget = 'content://x/document/out';

  @override
  Future<List<MediaStoreEntryMsg>> mediaStorePage(
    List<PickKindMsg> kinds,
    int? modifiedSinceMs,
    int offset,
    int limit,
  ) async => media.skip(offset).take(limit).toList();

  @override
  Future<String?> createSaveTarget(
    String suggestedName,
    String mimeType,
  ) async => saveTarget;

  @override
  Future<int> openWrite(String uri) async => 7;

  @override
  Future<void> write(int handle, Uint8List data) async {
    if (failWith != null) throw failWith!;
    writes.add(data.length);
  }

  @override
  Future<void> closeWrite(int handle, bool abort) async =>
      writes.add(abort ? 'abort' : 'close');

  @override
  Future<DocumentEntryMsg> statDocument(String uri) async => throw failWith!;

  @override
  Future<void> watch(String grantId) async => watched.add('+$grantId');

  @override
  Future<void> unwatch(String grantId) async => watched.add('-$grantId');
}

MediaStoreEntryMsg _entry(int i) => MediaStoreEntryMsg(
  uri: 'content://media/external/video/media/$i',
  relativePath: 'Movies/',
  name: '$i.mkv',
  size: i,
  modifiedMs: 1000 * i,
  kind: PickKindMsg.video,
);

void main() {
  late _FakeApi api;
  late StreamController<StorageChangeMsg> events;
  late AndroidStorage storage;

  setUp(() {
    api = _FakeApi();
    events = StreamController.broadcast();
    storage = AndroidStorage(api: api, events: () => events.stream);
  });

  test('LIB-002 MediaStore entries page until a short page', () async {
    api.media.addAll(List.generate(AndroidStorage.pageSize + 3, _entry));
    final all = await storage
        .mediaStoreEntries(kinds: {PickKind.video})
        .toList();
    expect(all, hasLength(AndroidStorage.pageSize + 3));
    expect(all.last.name, '${AndroidStorage.pageSize + 2}.mkv');
    expect(all.first.kind, PickKind.video);
    expect(all[2].modified, DateTime.fromMillisecondsSinceEpoch(2000));
  });

  test('FILE-002 saveFile coalesces chunks and closes', () async {
    final uri = await storage.saveFile(
      suggestedName: 'a',
      mimeType: 'text/plain',
      content: Stream.fromIterable(
        List.generate(5, (_) => List.filled(100000, 1)),
      ),
    );
    expect(uri, Uri.parse('content://x/document/out'));
    expect(api.writes, [300000, 200000, 'close']);
  });

  test('FILE-002 saveFile aborts the partial file on failure', () async {
    api.failWith = PlatformException(code: 'io', message: 'disk full');
    await expectLater(
      storage.saveFile(
        suggestedName: 'a',
        mimeType: 'text/plain',
        content: Stream.value(List.filled(10, 1)),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(api.writes, ['abort']);
  });

  test('FILE-002 saveFile returns null when the picker is cancelled', () async {
    api.saveTarget = null;
    expect(
      await storage.saveFile(
        suggestedName: 'a',
        mimeType: 'text/plain',
        content: const Stream.empty(),
      ),
      isNull,
    );
  });

  test('LIB-003 changes() watches one grant and filters events', () async {
    final got = <Uri>[];
    final sub = storage.changes('g1').listen(got.add);
    await pumpEventQueue();
    events
      ..add(StorageChangeMsg(grantId: 'g2', uri: 'content://b'))
      ..add(StorageChangeMsg(grantId: 'g1', uri: 'content://a'));
    await pumpEventQueue();
    await sub.cancel();
    expect(got, [Uri.parse('content://a')]);
    expect(api.watched, ['+g1', '-g1']);
  });

  test('SYS-007 module error codes map to dart:io exceptions', () async {
    api.failWith = PlatformException(code: 'notFound', message: 'gone');
    await expectLater(
      storage.statDocument(Uri.parse('content://x')),
      throwsA(isA<PathNotFoundException>()),
    );
    api.failWith = PlatformException(code: 'permissionDenied');
    await expectLater(
      storage.statDocument(Uri.parse('content://x')),
      throwsA(isA<PathAccessException>()),
    );
    api.failWith = PlatformException(code: 'unsupported');
    await expectLater(
      storage.statDocument(Uri.parse('content://x')),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
