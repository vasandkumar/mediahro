import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/organise/folder_tree.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';

PhotoEntry e(int id, int source, String rel) => PhotoEntry(
  id: id,
  sourceId: source,
  relPath: rel,
  name: rel.split('/').last,
  ext: 'jpg',
  isVideo: false,
  size: 1,
  mtime: DateTime(2026),
  date: DateTime(2026),
);

void main() {
  final entries = [
    e(1, 1, 'IMG_1.jpg'),
    e(2, 1, 'Trips/Paris/a.jpg'),
    e(3, 1, 'Trips/Paris/b.jpg'),
    e(4, 1, 'Trips/Rome/c.jpg'),
    e(5, 1, 'trips/Rome/d.jpg'),
    e(6, 2, 'Camera/x.jpg'),
  ];

  test('IMG-005 folders nest by path and count photos below them', () {
    final trees = buildFolderTrees(entries);
    expect(trees.keys, {1, 2});
    final root = trees[1]!;
    expect(root.photos.map((p) => p.id), [1]);
    expect(root.total, 5);
    final trips = root.find('Trips')!;
    expect(trips.photos, isEmpty);
    expect(trips.total, 3);
    expect(trips.find('Paris')!.photos.map((p) => p.id), [2, 3]);
    expect(trips.sortedChildren.map((c) => c.name), ['Paris', 'Rome']);
  });

  test('IMG-005 folder names that differ only in case stay separate', () {
    final root = buildFolderTrees(entries)[1]!;
    expect(root.sortedChildren.map((c) => c.name), ['Trips', 'trips']);
  });

  test('IMG-005 find returns null for a path that is not there', () {
    final root = buildFolderTrees(entries)[1]!;
    expect(root.find('Trips/Berlin'), isNull);
    expect(root.find(''), same(root));
  });

  test('IMG-005 sources are separate trees', () {
    final other = buildFolderTrees(entries)[2]!;
    expect(other.total, 1);
    expect(other.find('Camera')!.path, 'Camera');
  });

  test('IMG-005 no photos, no folders', () {
    expect(buildFolderTrees(const []), isEmpty);
  });
}
