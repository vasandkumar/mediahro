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
/// name, size or picture is ever written outside it. Opening needs the
/// keystore's master key (a handle) and the PIN-derived token; the token
/// binds the index, so without the PIN nothing in the folder can be read,
/// not even by someone who can use the keystore.
final class VaultContainer {
  VaultContainer._(
    this.directory,
    this.crypto,
    this.master,
    this._token,
    this._items,
  ) : _sealer = VaultSealer(crypto);

  final Directory directory;
  final VaultCryptoFacade crypto;
  final VaultKeyHandle master;
  final VaultSealer _sealer;
  Uint8List _token;
  List<VaultItem> _items;
  bool _closed = false;

  static const String indexName = 'index.mv';

  File get _index =>
      File('${directory.path}${Platform.pathSeparator}$indexName');

  File _file(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.mv');

  File _thumb(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.tm');

  /// Makes the folder with an empty index.
  static Future<VaultContainer> create({
    required Directory directory,
    required VaultCryptoFacade crypto,
    required VaultKeyHandle master,
    required Uint8List token,
  }) async {
    await directory.create(recursive: true);
    final nomedia = File('${directory.path}${Platform.pathSeparator}.nomedia');
    if (!nomedia.existsSync()) await nomedia.writeAsBytes(const []);
    final c = VaultContainer._(
      directory,
      crypto,
      master,
      Uint8List.fromList(token),
      [],
    );
    await c._saveIndex();
    return c;
  }

  /// Opens the folder; throws [VaultCorrupt] when [token] is not the one the
  /// index was sealed with (a wrong PIN looks like a damaged index).
  static Future<VaultContainer> open({
    required Directory directory,
    required VaultCryptoFacade crypto,
    required VaultKeyHandle master,
    required Uint8List token,
  }) async {
    final file = File('${directory.path}${Platform.pathSeparator}$indexName');
    if (!file.existsSync()) throw const VaultCorrupt('no index');
    final reader = await VaultReader.open(
      crypto: crypto,
      source: MemoryVaultSource(await file.readAsBytes()),
      master: master,
      secret: token,
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
    return VaultContainer._(
      directory,
      crypto,
      master,
      Uint8List.fromList(token),
      items,
    );
  }

  void _live() {
    if (_closed) throw const VaultLocked();
  }

  Future<void> _writeSealed(
    File target,
    Uint8List plain, {
    required bool embedKey,
  }) async {
    final key = await crypto.newFileKey(master);
    final part = File('${target.path}.part');
    final raf = await part.open(mode: FileMode.write);
    try {
      await _sealer.seal(
        key: key,
        plain: Stream.value(plain),
        plainLength: plain.length,
        out: (b) async => await raf.writeFrom(b),
        embedKey: embedKey,
        secret: _token,
      );
      await raf.flush();
    } finally {
      await raf.close();
    }
    await part.rename(target.path);
  }

  Future<void> _saveIndex() async {
    final json = utf8.encode(jsonEncode([for (final i in _items) i.toJson()]));
    await _writeSealed(_index, Uint8List.fromList(json), embedKey: true);
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
  }) async {
    _live();
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
    _items = [..._items, item];
    try {
      await _saveIndex();
    } on Object {
      _items = [
        for (final i in _items)
          if (i.id != id) i,
      ];
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    return item;
  }

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
  Future<void> putThumbnail(String id, Uint8List bytes) async {
    _live();
    await _writeSealed(_thumb(id), bytes, embedKey: true);
  }

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
        secret: _token,
      );
      return await reader.readAll();
    } on VaultCorrupt {
      return null;
    }
  }

  /// Takes [id] out of the vault for good.
  Future<void> remove(String id) async {
    _live();
    _items = [
      for (final i in _items)
        if (i.id != id) i,
    ];
    await _saveIndex();
    for (final f in [_file(id), _thumb(id)]) {
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Binds the vault to a new PIN token: the index and the thumbnails are
  /// sealed again (the files themselves do not depend on the PIN).
  Future<void> rekey(Uint8List newToken) async {
    _live();
    final thumbs = <String, Uint8List>{};
    for (final i in _items) {
      final t = await thumbnail(i.id);
      if (t != null) thumbs[i.id] = t;
    }
    final old = _token;
    _token = Uint8List.fromList(newToken);
    await _saveIndex();
    for (final e in thumbs.entries) {
      await _writeSealed(_thumb(e.key), e.value, embedKey: true);
    }
    old.fillRange(0, old.length, 0);
  }

  /// The vault is locked: the token is zeroed and nothing is listed.
  void close() {
    if (_closed) return;
    _closed = true;
    _token.fillRange(0, _token.length, 0);
    _items = const [];
  }

  bool get isClosed => _closed;

  /// A copy of the token, for the manager to seal behind the fingerprint.
  /// The caller zeroes it.
  Uint8List tokenCopy() {
    _live();
    return Uint8List.fromList(_token);
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
