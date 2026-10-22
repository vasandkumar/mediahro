import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

/// The URIs an archive file system lists must lie below the root it is mounted
/// at, because `IsolateFileSystem.pathOf` refuses anything else. A book mounts
/// each archive at `archive:///<id>/`; with entry URIs that ignored the id, a
/// folder found in a listing could not be listed in turn and every archive with
/// a folder was "unreadable" on the phone (IMG-017, batch 6).
void main() {
  final root = Uri(scheme: 'archive', path: '/9f2c4d1a/');

  /// A file system that only maps URIs, as a book's archive file system does.
  IsolateFileSystem fsAt(Uri root) => IsolateFileSystem(
    root: root,
    schemes: const {'archive'},
    debugName: 'test',
    factory: () => throw UnimplementedError(),
  );

  test('IMG-017 an entry URI is below the mount point and maps back', () {
    final fs = fsAt(root);
    for (final path in [
      'page.jpg',
      'ch1/1.jpg',
      'ch1/sub dir/2.jpg',
      'Ünï/cödé.jpg',
      'a%b/c.jpg',
    ]) {
      expect(fs.pathOf(archiveEntryUri(root, path)), path, reason: path);
    }
  });

  test('IMG-017 the archive itself and a folder map back', () {
    final fs = fsAt(root);
    expect(archiveEntryUri(root, ''), root);
    expect(fs.pathOf(archiveEntryUri(root, '')), '');
    expect(archiveEntryUri(root, 'ch1/').path, '/9f2c4d1a/ch1/');
    expect(fs.pathOf(archiveEntryUri(root, 'ch1/')), 'ch1');
  });

  test('IMG-017 a root without a trailing slash is treated as a folder', () {
    final bare = Uri(scheme: 'archive', path: '/9f2c4d1a');
    expect(archiveEntryUri(bare, 'ch1/1.jpg').path, '/9f2c4d1a/ch1/1.jpg');
  });

  test('IMG-017 the plain root keeps the old URIs', () {
    final plain = Uri.parse('archive:///');
    expect(
      archiveEntryUri(plain, 'page 01.jpg').toString(),
      'archive:///page%2001.jpg',
    );
    expect(archiveEntryUri(plain, ''), plain);
    expect(archiveEntryUri(Uri(scheme: 'archive'), 'a.jpg').path, '/a.jpg');
  });

  test('IMG-017 a URI from a different archive is outside the root', () {
    final fs = fsAt(root);
    final other = Uri(scheme: 'archive', path: '/00000000/ch1/1.jpg');
    expect(() => fs.pathOf(other), throwsA(isA<VirtualFileException>()));
  });
}
