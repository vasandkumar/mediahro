import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/features/photos/vault/vault_crypto.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// One item in the vault (IMG-011, PRIV-007). Names and facts live only in
/// the encrypted index; the files are called by a random id.
@immutable
final class VaultItem {
  const VaultItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.size,
    required this.addedAt,
    this.takenAt,
    this.width,
    this.height,
  });

  /// 32 hex characters; the file is `<id>.mv`.
  final String id;
  final String name;

  /// `image`, `video` or `audio`.
  final String kind;

  /// Size of the original in bytes.
  final int size;
  final DateTime addedAt;
  final DateTime? takenAt;
  final int? width;
  final int? height;

  String get ext {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  DateTime get date => takenAt ?? addedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'size': size,
    'added': addedAt.millisecondsSinceEpoch,
    if (takenAt != null) 'taken': takenAt!.millisecondsSinceEpoch,
    if (width != null) 'w': width,
    if (height != null) 'h': height,
  };

  static VaultItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    final kind = j['kind'];
    final size = j['size'];
    final added = j['added'];
    if (id is! String ||
        name is! String ||
        kind is! String ||
        size is! int ||
        added is! int) {
      return null;
    }
    final taken = j['taken'];
    return VaultItem(
      id: id,
      name: name,
      kind: kind,
      size: size,
      addedAt: DateTime.fromMillisecondsSinceEpoch(added),
      takenAt: taken is int ? DateTime.fromMillisecondsSinceEpoch(taken) : null,
      width: j['w'] as int?,
      height: j['h'] as int?,
    );
  }
}

/// A vault file as a [VirtualFile], so the image pipeline reads it like any
/// other photo (and a player can, once it takes a custom source). Reads
/// decrypt only the chunks they touch.
final class VaultFile implements VirtualFile {
  VaultFile._(this.uri, this._reader, this._raf);

  @override
  final Uri uri;
  final VaultReader _reader;
  final RandomAccessFile _raf;

  @override
  Future<int?> length() async => _reader.plainLength;

  @override
  Future<Uint8List> read(int offset, int length) =>
      _reader.read(offset, length);

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() => _raf.close();
}

final class _FileSource implements VaultSource {
  _FileSource(this.raf);

  final RandomAccessFile raf;

  @override
  Future<int> length() => raf.length();

  @override
  Future<Uint8List> read(int offset, int length) async {
    await raf.setPosition(offset);
    return await raf.read(length);
  }
}

/// A folder of encrypted files with an encrypted index (IMG-011). No plain
/// name, size or picture is ever written outside it.
final class VaultStore {
  VaultStore({required this.directory, required this.crypto});

  final Directory directory;
  final VaultCrypto crypto;
  List<VaultItem>? _items;

  File get _index => File('${directory.path}${Platform.pathSeparator}index.mv');

  File _file(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.mv');

  /// Opens the folder: creates it (with `.nomedia`, so gallery apps skip it)
  /// and reads the index; throws [VaultCorrupt] if the key does not fit.
  Future<void> open() async {
    await directory.create(recursive: true);
    final nomedia = File('${directory.path}${Platform.pathSeparator}.nomedia');
    if (!nomedia.existsSync()) await nomedia.writeAsBytes(const []);
    if (!_index.existsSync()) {
      _items = [];
      await _saveIndex();
      return;
    }
    final plain = await crypto.unsealBytes(await _index.readAsBytes());
    final data = jsonDecode(utf8.decode(plain));
    _items = [
      if (data is List)
        for (final j in data)
          if (VaultItem.fromJson(j) case final VaultItem v) v,
    ];
  }

  Future<void> _saveIndex() async {
    final json = utf8.encode(jsonEncode([for (final i in _items!) i.toJson()]));
    final sealed = await crypto.sealBytes(Uint8List.fromList(json));
    final part = File('${_index.path}.part');
    await part.writeAsBytes(sealed, flush: true);
    await part.rename(_index.path);
  }

  /// Everything in the vault, newest first.
  List<VaultItem> list() =>
      [...?_items]..sort((a, b) => b.date.compareTo(a.date));

  VaultItem? byId(String id) {
    for (final i in _items ?? const <VaultItem>[]) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Encrypts [content] ([size] bytes) into the vault.
  Future<VaultItem> add({
    required String name,
    required String kind,
    required Stream<List<int>> content,
    required int size,
    DateTime? takenAt,
    int? width,
    int? height,
    DateTime? now,
  }) async {
    final id = _hex(VaultCrypto.randomBytes(16));
    final file = _file(id);
    final sink = file.openWrite();
    try {
      await crypto.seal(content, size, sink.add);
      await sink.close();
    } on Object {
      try {
        await sink.close();
      } on Object {
        // Already failed once.
      }
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    final item = VaultItem(
      id: id,
      name: name,
      kind: kind,
      size: size,
      addedAt: now ?? DateTime.now(),
      takenAt: takenAt,
      width: width,
      height: height,
    );
    _items!.add(item);
    await _saveIndex();
    return item;
  }

  /// The decrypted file, for the image pipeline.
  Future<VaultFile> openFile(String id) async {
    final raf = await _file(id).open();
    try {
      final reader = await crypto.open(_FileSource(raf));
      return VaultFile._(Uri.parse('vault://local/$id'), reader, raf);
    } on Object {
      await raf.close();
      rethrow;
    }
  }

  /// All bytes of an item (restoring it).
  Future<Uint8List> readAll(String id) async {
    final f = await openFile(id);
    try {
      return await f.read(0, await f.length() ?? 0);
    } finally {
      await f.close();
    }
  }

  /// Takes [id] out of the vault for good.
  Future<void> remove(String id) async {
    _items!.removeWhere((i) => i.id == id);
    await _saveIndex();
    final f = _file(id);
    if (f.existsSync()) f.deleteSync();
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
