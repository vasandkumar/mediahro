import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// A source that behaves like Android's SAF: `create` over an existing name
/// is refused, a rename needs a free target, and every call can be made to
/// fail or to lose bytes.
final class _SafLike implements MutableFileSystem {
  final Map<String, Uint8List> files = {};
  final List<String> log = [];

  /// Calls (`create:name`, `rename:old->new`, `delete:name`) that throw.
  final Set<String> failing = {};

  /// Writes keep only this many bytes (a disk that lost the end).
  int? truncateWritesTo;

  static String _key(Uri uri) => uri.pathSegments.last;

  Uri uriOf(String name) =>
      Uri.parse('saf://tree/p/${Uri.encodeComponent(name)}');

  void _maybeFail(String what, Uri uri) {
    if (failing.contains(what)) {
      throw VirtualFileException(VirtualFileError.io, uri, 'injected: $what');
    }
  }

  @override
  Set<String> get schemes => {'saf'};

  @override
  Set<VirtualFsCapability> get capabilities => {
    VirtualFsCapability.write,
    VirtualFsCapability.rename,
    VirtualFsCapability.delete,
  };

  @override
  Future<VirtualFile> open(Uri uri) async {
    final data = files[_key(uri)];
    if (data == null) {
      throw VirtualFileException(VirtualFileError.notFound, uri);
    }
    return _Reader(uri, data);
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final data = files[_key(uri)];
    if (data == null) {
      throw VirtualFileException(VirtualFileError.notFound, uri);
    }
    return VirtualEntry(
      uri: uri,
      name: _key(uri),
      isDirectory: false,
      size: data.length,
    );
  }

  @override
  Stream<VirtualEntry> list(Uri directory) async* {}

  @override
  Future<Uri> createDirectory(Uri parent, String name) =>
      throw UnimplementedError();

  @override
  Future<Uri> move(Uri uri, Uri directory) => throw UnimplementedError();

  @override
  Future<Uri> rename(Uri uri, String newName) async {
    final from = _key(uri);
    log.add('rename:$from->$newName');
    _maybeFail('rename:$from->$newName', uri);
    if (!files.containsKey(from)) {
      throw VirtualFileException(VirtualFileError.notFound, uri);
    }
    if (files.containsKey(newName)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    files[newName] = files.remove(from)!;
    return uriOf(newName);
  }

  @override
  Future<void> delete(Uri uri, {bool recursive = false}) async {
    final name = _key(uri);
    log.add('delete:$name');
    _maybeFail('delete:$name', uri);
    files.remove(name);
  }

  @override
  Future<VirtualFileWriter> create(Uri uri) async {
    final name = _key(uri);
    log.add('create:$name');
    _maybeFail('create:$name', uri);
    if (files.containsKey(name)) {
      throw VirtualFileException(VirtualFileError.alreadyExists, uri);
    }
    return _Writer(this, uri, name);
  }
}

final class _Reader implements VirtualFile {
  _Reader(this.uri, this.data);

  @override
  final Uri uri;
  final Uint8List data;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => data.length;

  @override
  Future<Uint8List> read(int offset, int length) async => Uint8List.sublistView(
    data,
    offset,
    (offset + length).clamp(0, data.length),
  );

  @override
  Future<void> close() async {}
}

final class _Writer implements VirtualFileWriter {
  _Writer(this.fs, this.uri, this.name);

  final _SafLike fs;
  @override
  final Uri uri;
  final String name;
  final BytesBuilder _buf = BytesBuilder();

  @override
  Future<void> write(List<int> bytes) async => _buf.add(bytes);

  @override
  Future<void> close() async {
    final all = _buf.takeBytes();
    final keep = fs.truncateWritesTo;
    fs.files[name] = keep == null || keep >= all.length
        ? all
        : Uint8List.sublistView(all, 0, keep);
  }

  @override
  Future<void> abort() async {}
}

Uint8List bytesOf(int n, int seed) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + seed) & 0xFF));

void main() {
  late _SafLike saf;
  late MountedImageIo io;
  late Uri photo;

  setUp(() {
    saf = _SafLike();
    final mounts = MountedFileSystems()..mount(Uri.parse('saf://tree/'), saf);
    io = MountedImageIo(mounts);
    photo = saf.uriOf('IMG_1.jpg');
    saf.files['IMG_1.jpg'] = bytesOf(1000, 1);
  });

  test(
    'IMG-009 replacing a SAF document works although create refuses',
    () async {
      final fresh = bytesOf(2000, 9);
      await io.replace(photo, fresh);
      expect(saf.files.keys, ['IMG_1.jpg']);
      expect(saf.files['IMG_1.jpg'], fresh);
    },
  );

  test('IMG-009 a file that is not there yet is simply created', () async {
    saf.files.clear();
    await io.replace(photo, bytesOf(10, 3));
    expect(saf.files.keys, ['IMG_1.jpg']);
  });

  test(
    'IMG-009 a failed temporary write leaves the original untouched',
    () async {
      final original = saf.files['IMG_1.jpg']!;
      saf.failing.add('create:.IMG_1.jpg.mediahro-tmp');
      await expectLater(
        io.replace(photo, bytesOf(2000, 9)),
        throwsA(isA<VirtualFileException>()),
      );
      expect(saf.files['IMG_1.jpg'], original);
      expect(saf.files.keys, ['IMG_1.jpg']);
    },
  );

  test('IMG-009 a copy that does not read back is never swapped in', () async {
    final original = saf.files['IMG_1.jpg']!;
    saf.truncateWritesTo = 1500;
    await expectLater(
      io.replace(photo, bytesOf(2000, 9)),
      throwsA(isA<VirtualFileException>()),
    );
    expect(saf.files['IMG_1.jpg'], original);
    expect(saf.files.keys, ['IMG_1.jpg']);
    expect(
      saf.log,
      isNot(contains('rename:IMG_1.jpg->.IMG_1.jpg.mediahro-bak')),
    );
  });

  test('IMG-009 if parking the original fails nothing has moved', () async {
    final original = saf.files['IMG_1.jpg']!;
    saf.failing.add('rename:IMG_1.jpg->.IMG_1.jpg.mediahro-bak');
    await expectLater(
      io.replace(photo, bytesOf(2000, 9)),
      throwsA(isA<VirtualFileException>()),
    );
    expect(saf.files['IMG_1.jpg'], original);
    expect(saf.files.keys, ['IMG_1.jpg']);
  });

  test('IMG-009 if the swap-in fails the original is put back', () async {
    final original = saf.files['IMG_1.jpg']!;
    saf.failing.add('rename:.IMG_1.jpg.mediahro-tmp->IMG_1.jpg');
    await expectLater(
      io.replace(photo, bytesOf(2000, 9)),
      throwsA(isA<VirtualFileException>()),
    );
    expect(saf.files['IMG_1.jpg'], original);
    expect(saf.files.keys, ['IMG_1.jpg']);
  });

  test(
    'IMG-009 a crash between the renames is repaired by the next replace',
    () async {
      // The original was parked and the new file never arrived.
      saf.files['.IMG_1.jpg.mediahro-bak'] = saf.files.remove('IMG_1.jpg')!;
      final fresh = bytesOf(300, 5);
      await io.replace(photo, fresh);
      expect(saf.files.keys, ['IMG_1.jpg']);
      expect(saf.files['IMG_1.jpg'], fresh);
    },
  );

  test(
    'IMG-009 a leftover parked copy is dropped when the original exists',
    () async {
      saf.files['.IMG_1.jpg.mediahro-bak'] = bytesOf(5, 5);
      await io.replace(photo, bytesOf(300, 5));
      expect(saf.files.keys, ['IMG_1.jpg']);
    },
  );

  test('IMG-009 names are encoded like the source does', () async {
    final spaced = saf.uriOf('Summer trip 1.jpg');
    saf.files['Summer trip 1.jpg'] = bytesOf(100, 2);
    await io.replace(spaced, bytesOf(200, 4));
    expect(saf.files.keys.toSet(), {'IMG_1.jpg', 'Summer trip 1.jpg'});
    expect(saf.files['Summer trip 1.jpg'], bytesOf(200, 4));
  });
}
