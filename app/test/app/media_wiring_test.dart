import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/media_wiring.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/scanner/probe_queue.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

final class _Prober implements MediaProber {
  _Prober(this.tag);

  final String tag;
  final calls = <ItemKind>[];

  @override
  Future<ProbeResult> probe(VirtualFile file, ItemRow item) async {
    calls.add(item.kind);
    return ProbeResult(title: tag);
  }
}

final class _Item implements ItemRow {
  _Item(this.kind);

  @override
  final ItemKind kind;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _File implements VirtualFile {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('IMG-003 probe router sends images to the image prober only', () async {
    final images = _Prober('img');
    final engine = _Prober('eng');
    final router = KindRoutingProber(images: images, fallback: engine);
    final file = _File();
    expect((await router.probe(file, _Item(ItemKind.image))).title, 'img');
    expect((await router.probe(file, _Item(ItemKind.video))).title, 'eng');
    expect((await router.probe(file, _Item(ItemKind.audio))).title, 'eng');
    expect(images.calls, [ItemKind.image]);
    expect(engine.calls, [ItemKind.video, ItemKind.audio]);
  });

  test(
    'IMG-003 probe router without an engine prober returns bare result',
    () async {
      final router = KindRoutingProber(images: _Prober('img'));
      final r = await router.probe(_File(), _Item(ItemKind.video));
      expect(r.title, isNull);
    },
  );
}
