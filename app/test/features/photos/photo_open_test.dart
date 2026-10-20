import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/features/photos/photo_open.dart';

import '../../core/seed.dart';

void main() {
  late LibraryDatabase db;
  late Seed seed;

  setUp(() {
    db = LibraryDatabase.memory();
    seed = Seed(db);
  });

  tearDown(() => db.close());

  Future<ItemRow> row(int id) =>
      (db.select(db.items)..where((i) => i.id.equals(id))).getSingle();

  test(
    'IMG-004 opening a photo from a folder pages through its neighbours',
    () async {
      final a = await seed.item('trip/a.jpg', kind: ItemKind.image);
      final b = await seed.item('trip/b.jpg', kind: ItemKind.image);
      final c = await seed.item('trip/c.jpg', kind: ItemKind.image);
      await seed.item('other/z.jpg', kind: ItemKind.image);
      await seed.item('trip/notes.mp3', kind: ItemKind.audio);
      final args = await viewerArgsFor(LibraryViews(db), await row(b));
      expect(args.entries.map((e) => e.id), [a, b, c]);
      expect(args.index, 1);
      expect(args.entries[1].name, 'b.jpg');
    },
  );

  test('IMG-004 a hidden or unlisted item still opens on its own', () async {
    final id = await seed.item(
      'x/solo.jpg',
      kind: ItemKind.image,
      hidden: true,
    );
    final args = await viewerArgsFor(LibraryViews(db), await row(id));
    expect(args.entries.map((e) => e.id), [id]);
    expect(args.index, 0);
  });

  test('IMG-003 index rows carry the embedded video and HDR markers', () async {
    final id = await seed.item(
      'm.jpg',
      kind: ItemKind.image,
      videoCodec: 'mp4',
      hdrType: 'gainmap',
    );
    final e = photoEntryFromItem(await row(id));
    expect(e.motionPhoto, isTrue);
    expect(e.hdr, isTrue);
    expect(e.isVideo, isFalse);
    expect(e.ext, 'jpg');
  });
}
