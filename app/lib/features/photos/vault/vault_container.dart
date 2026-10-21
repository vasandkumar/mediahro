import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/features/photos/vault/vault_framing.dart';
import 'package:mediahro/platform/vault_crypto.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// The vault was locked while something was still using it.
final class VaultLocked implements Exception {
  const VaultLocked();

  @override
  String toString() => 'VaultLocked';
}

/// One item in a vault (IMG-011, PRIV-007). Names, facts and the item's
/// wrapped key live only in the encrypted index; the files are called by a
/// random id.
@immutable
final class VaultItem {
  const VaultItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.size,
    required this.addedAt,
    required this.key,
    this.takenAt,
    this.width,
    this.height,
    this.tags = const [],
    this.halfStars,
    this.favourite = false,
    this.label,
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

  /// The file key, wrapped by the keystore key.
  final Uint8List key;

  /// What the library knew of the photo, kept so taking it out brings it
  /// back (tags, rating in half stars, favourite, colour label).
  final List<String> tags;
  final int? halfStars;
  final bool favourite;
  final String? label;

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
    'key': base64Encode(key),
    if (takenAt != null) 'taken': takenAt!.millisecondsSinceEpoch,
    if (width != null) 'w': width,
    if (height != null) 'h': height,
    if (tags.isNotEmpty) 'tags': tags,
    if (halfStars != null) 'stars': halfStars,
    if (favourite) 'fav': true,
    if (label != null) 'label': label,
  };

  static VaultItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    final kind = j['kind'];
    final size = j['size'];
    final added = j['added'];
    final key = j['key'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        name is! String ||
        kind is! String ||
        size is! int ||
        added is! int ||
        key is! String) {
      return null;
    }
    final taken = j['taken'];
    final tags = j['tags'];
    return VaultItem(
      id: id,
      name: name,
      kind: kind,
      size: size,
      addedAt: DateTime.fromMillisecondsSinceEpoch(added),
      key: base64Decode(key),
      takenAt: taken is int ? DateTime.fromMillisecondsSinceEpoch(taken) : null,
      width: j['w'] as int?,
      height: j['h'] as int?,
      tags: tags is List
          ? [
              for (final t in tags)
                if (t is String) t,
            ]
          : const [],
      halfStars: j['stars'] as int?,
      favourite: j['fav'] == true,
      label: j['label'] as String?,
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
  final RandomAccessFile? _raf;

  @override
  Future<int?> length() async => _reader.plainLength;

  @override
  Future<Uint8List> read(int offset, int length) =>
      _reader.read(offset, length);

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async {
    _reader.forget();
    await _raf?.close();
  }
}

/// A file read under a lock: the position and the read are two calls, so
/// two readers must not interleave.
final class _FileSource implements VaultSource {
  _FileSource(this.raf);

  final RandomAccessFile raf;
  Future<void> _tail = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() run) {
    final result = _tail.then((_) => run());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<int> length() => _locked(raf.length);

  @override
  Future<Uint8List> read(int offset, int length) => _locked(() async {
    await raf.setPosition(offset);
    return await raf.read(length);
  });
}

/// A folder of encrypted files with an encrypted index (IMG-011). No plain
/// name, size or picture is ever written outside it. Opening needs a keystore
/// handle opened with the container's own secret (ADR-039 amendment 2): the
/// keys of the index, the pictures and the files are all wrapped under it, so
/// without the secret (which only the right PIN or the fingerprint gives)
/// nothing here can be read. The PIN is not part of this class; changing it
/// does not touch the folder.
///
/// Everything that changes the folder runs one at a time, and a lock that
/// arrives in the middle lets work already under way finish.
final class VaultContainer {
  VaultContainer._(this.directory, this.crypto, this.master, this._items)
    : _sealer = VaultSealer(crypto);

  final Directory directory;
  final VaultCryptoFacade crypto;

  /// The handle opened with the container's secret.
  final VaultKeyHandle master;
  final VaultSealer _sealer;
  List<VaultItem> _items;
  bool _closed = false;
  Future<void> _tail = Future<void>.value();

  static const String indexName = 'index.mv';

  String get _name => directory.path.split(Platform.pathSeparator).last;

  File get _index =>
      File('${directory.path}${Platform.pathSeparator}$indexName');

  File _file(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.mv');

  File _thumb(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.tm');

  /// What the index of the folder named [name] is for.
  static Uint8List _indexContext(String name) =>
      Uint8List.fromList(utf8.encode('index:$name'));

  static Uint8List _thumbContext(String id) =>
      Uint8List.fromList(utf8.encode('thumb:$id'));

  /// Makes the folder with an empty index.
  static Future<VaultContainer> create({
    required Directory directory,
    required VaultCryptoFacade crypto,
    required VaultKeyHandle master,
  }) async {
    await directory.create(recursive: true);
    final nomedia = File('${directory.path}${Platform.pathSeparator}.nomedia');
    if (!nomedia.existsSync()) await nomedia.writeAsBytes(const []);
    final c = VaultContainer._(directory, crypto, master, []);
    await c._serial(c._saveIndex);
    return c;
  }

  /// Opens the folder; throws [VaultCorrupt] when the index cannot be read
  /// (damaged, or sealed for another folder) and the facade's
  /// [VaultCryptoException] when [master] is not the handle it needs.
  static Future<VaultContainer> open({
    required Directory directory,
    required VaultCryptoFacade crypto,
    required VaultKeyHandle master,
  }) async {
    final file = File('${directory.path}${Platform.pathSeparator}$indexName');
    if (!file.existsSync()) throw const VaultCorrupt('no index');
    final reader = await VaultReader.open(
      crypto: crypto,
      source: MemoryVaultSource(await file.readAsBytes()),
      master: master,
      context: _indexContext(directory.path.split(Platform.pathSeparator).last),
    );
    final plain = await reader.readAll();
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const VaultCorrupt('index is not readable');
    }
    final items = <VaultItem>[
      if (data is List)
        for (final j in data)
          if (VaultItem.fromJson(j) case final VaultItem v) v,
    ];
    return VaultContainer._(directory, crypto, master, items);
  }

  void _live() {
    if (_closed) throw const VaultLocked();
  }

  /// Runs [op] after everything before it, and refuses once the vault is
  /// locked.
  Future<T> _serial<T>(Future<T> Function() op) {
    _live();
    final done = Completer<T>();
    final previous = _tail;
    _tail = done.future.then((_) {}, onError: (_) {});
    unawaited(
      previous.then((_) async {
        try {
          if (_closed) throw const VaultLocked();
          done.complete(await op());
        } on Object catch (e, st) {
          done.completeError(e, st);
        }
      }),
    );
    return done.future;
  }

  Future<void> _writeSealed(
    File target,
    Uint8List plain, {
    required Uint8List context,
  }) async {
    final key = await crypto.newFileKey(master);
    final part = File('${target.path}.part');
    try {
      final raf = await part.open(mode: FileMode.write);
      try {
        await _sealer.seal(
          key: key,
          plain: Stream.value(plain),
          plainLength: plain.length,
          out: (b) async => await raf.writeFrom(b),
          embedKey: true,
          context: context,
        );
        await raf.flush();
      } finally {
        await raf.close();
      }
      await part.rename(target.path);
    } on Object {
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } on FileSystemException {
          // Left for the next write over it.
        }
      }
      rethrow;
    }
  }

  Future<void> _saveIndex() async {
    final json = utf8.encode(jsonEncode([for (final i in _items) i.toJson()]));
    await _writeSealed(
      _index,
      Uint8List.fromList(json),
      context: _indexContext(_name),
    );
  }

  /// Everything in the vault, newest first.
  List<VaultItem> list() {
    _live();
    return [..._items]..sort((a, b) => b.date.compareTo(a.date));
  }

  VaultItem? byId(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Encrypts [content] ([size] bytes) into the vault: written, forced to
  /// disk and read back (the last chunk is decrypted) before the item is
  /// listed, so the caller may remove the original.
  Future<VaultItem> add({
    required String name,
    required String kind,
    required Stream<List<int>> content,
    required int size,
    DateTime? takenAt,
    int? width,
    int? height,
    List<String> tags = const [],
    int? halfStars,
    bool favourite = false,
    String? label,
    DateTime? now,
  }) => _serial(() async {
    final id = _hex(randomBytes(16));
    final file = _file(id);
    final key = await crypto.newFileKey(master);
    try {
      final raf = await file.open(mode: FileMode.write);
      try {
        await _sealer.seal(
          key: key,
          plain: content,
          plainLength: size,
          out: (b) async => await raf.writeFrom(b),
        );
        await raf.flush();
      } finally {
        await raf.close();
      }
      await _verify(file, key, size);
    } on Object {
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    final item = VaultItem(
      id: id,
      name: name,
      kind: kind,
      size: size,
      addedAt: now ?? DateTime.now(),
      key: key.bytes,
      takenAt: takenAt,
      width: width,
      height: height,
      tags: tags,
      halfStars: halfStars,
      favourite: favourite,
      label: label,
    );
    final before = _items;
    _items = [..._items, item];
    try {
      await _saveIndex();
    } on Object {
      _items = before;
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    return item;
  });

  Future<void> _verify(File file, WrappedKey key, int size) async {
    final raf = await file.open();
    try {
      final reader = await VaultReader.open(
        crypto: crypto,
        source: _FileSource(raf),
        key: key,
      );
      if (reader.plainLength != size) throw const VaultCorrupt('wrong length');
      // First and last chunk authenticate: the ends are where cut-off and
      // lost writes show.
      await reader.read(0, 1);
      if (size > 0) await reader.read(size - 1, 1);
    } finally {
      await raf.close();
    }
  }

  /// The decrypted file, for the image pipeline.
  Future<VaultFile> openFile(String id) async {
    _live();
    final item = byId(id);
    if (item == null) throw const VaultCorrupt('no such item');
    final raf = await _file(id).open();
    try {
      final key = await crypto.adoptFileKey(master, item.key);
      final reader = await VaultReader.open(
        crypto: crypto,
        source: _FileSource(raf),
        key: key,
      );
      return VaultFile._(Uri.parse('vault://local/$id'), reader, raf);
    } on Object {
      await raf.close();
      rethrow;
    }
  }

  /// All bytes of an item.
  Future<Uint8List> readAll(String id) async {
    final f = await openFile(id);
    try {
      return await f.read(0, await f.length() ?? 0);
    } finally {
      await f.close();
    }
  }

  /// Stores a small picture of [id] (sealed like everything else) so the grid
  /// never decrypts the whole file.
  Future<void> putThumbnail(String id, Uint8List bytes) => _serial(
    () => _writeSealed(_thumb(id), bytes, context: _thumbContext(id)),
  );

  /// The stored picture of [id], or null when there is none.
  Future<Uint8List?> thumbnail(String id) async {
    _live();
    final f = _thumb(id);
    if (!f.existsSync()) return null;
    try {
      final reader = await VaultReader.open(
        crypto: crypto,
        source: MemoryVaultSource(await f.readAsBytes()),
        master: master,
        context: _thumbContext(id),
      );
      return await reader.readAll();
    } on VaultCorrupt {
      return null;
    }
  }

  /// Takes [id] out of the vault for good.
  Future<void> remove(String id) => _serial(() async {
    final before = _items;
    _items = [
      for (final i in _items)
        if (i.id != id) i,
    ];
    try {
      await _saveIndex();
    } on Object {
      _items = before;
      rethrow;
    }
    for (final f in [_file(id), _thumb(id)]) {
      if (f.existsSync()) f.deleteSync();
    }
  });

  /// The vault is locked: nothing more starts, and work under way finishes.
  void close() {
    if (_closed) return;
    _closed = true;
    _items = const [];
  }

  bool get isClosed => _closed;

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
