import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A vault file does not match its key: wrong key, damaged, cut short or
/// changed.
final class VaultCorrupt implements Exception {
  const VaultCorrupt(this.reason);

  final String reason;

  @override
  String toString() => 'VaultCorrupt($reason)';
}

/// Random access to the bytes of an encrypted file.
abstract interface class VaultSource {
  Future<int> length();
  Future<Uint8List> read(int offset, int length);
}

/// Bytes in memory as a [VaultSource] (tests, small files).
final class MemoryVaultSource implements VaultSource {
  MemoryVaultSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async => Uint8List.sublistView(
    bytes,
    offset.clamp(0, bytes.length),
    (offset + length).clamp(0, bytes.length),
  );
}

/// The vault's file format (IMG-011, PRIV-007, ADR-008): AES-256-GCM in
/// 64 KiB chunks under a random key per file, that key wrapped by the vault
/// master key. Chunks are authenticated with their position and whether they
/// are the last, so reordering, cutting and splicing are noticed; any byte
/// range can be read without decrypting the rest.
///
/// ```text
/// "MVLT" | version 1 | 3 reserved | fileId[16] | plainLength u64 |
/// chunkSize u32 | keyNonce[12] | wrappedKey[32 + 16 tag]      = 96 bytes
/// then per chunk: cipher[min(chunkSize, left)] | tag[16]
/// ```
final class VaultCrypto {
  VaultCrypto(Uint8List masterKey) : _master = SecretKey(masterKey);

  static const int chunkSize = 64 * 1024;
  static const int headerSize = 96;
  static const int tagSize = 16;
  static const int version = 1;
  static const List<int> magic = [0x4D, 0x56, 0x4C, 0x54];

  final SecretKey _master;
  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _random = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  /// Size of the encrypted form of [plainLength] bytes.
  static int sealedLength(int plainLength) =>
      headerSize +
      plainLength +
      ((plainLength + chunkSize - 1) ~/ chunkSize) * tagSize;

  static Uint8List _keyAad(Uint8List id, int plainLength, int chunk) {
    final b = BytesBuilder()
      ..add(const [0x4D, 0x56, 0x4C, 0x4B])
      ..add(id)
      ..add(_u64(plainLength))
      ..add(_u32(chunk));
    return b.takeBytes();
  }

  static Uint8List _chunkAad(Uint8List id, int index, {required bool last}) {
    final b = BytesBuilder()
      ..add(magic)
      ..add(id)
      ..add(_u32(index))
      ..addByte(last ? 1 : 0);
    return b.takeBytes();
  }

  static Uint8List _u32(int v) =>
      (ByteData(4)..setUint32(0, v)).buffer.asUint8List();

  static Uint8List _u64(int v) =>
      (ByteData(8)..setUint64(0, v)).buffer.asUint8List();

  /// 12-byte nonce: 8 bytes of the file id and the chunk number. The key is
  /// new for every file, so a nonce never repeats under one key.
  static Uint8List _nonce(Uint8List id, int index) {
    final n = Uint8List(12)..setRange(0, 8, id);
    ByteData.sublistView(n).setUint32(8, index);
    return n;
  }

  /// Encrypts [plain] ([plainLength] bytes in all) into [out]. The stream may
  /// deliver any chunking; it must deliver exactly [plainLength] bytes.
  Future<void> seal(
    Stream<List<int>> plain,
    int plainLength,
    void Function(List<int>) out,
  ) async {
    final id = randomBytes(16);
    final fileKey = randomBytes(32);
    final keyNonce = randomBytes(12);
    final wrapped = await _aes.encrypt(
      fileKey,
      secretKey: _master,
      nonce: keyNonce,
      aad: _keyAad(id, plainLength, chunkSize),
    );
    out(
      (BytesBuilder()
            ..add(magic)
            ..addByte(version)
            ..add(const [0, 0, 0])
            ..add(id)
            ..add(_u64(plainLength))
            ..add(_u32(chunkSize))
            ..add(keyNonce)
            ..add(wrapped.cipherText)
            ..add(wrapped.mac.bytes))
          .takeBytes(),
    );
    final key = SecretKey(fileKey);
    final buffer = BytesBuilder(copy: false);
    var index = 0;
    var sent = 0;
    Future<void> flush(Uint8List chunk, {required bool last}) async {
      final box = await _aes.encrypt(
        chunk,
        secretKey: key,
        nonce: _nonce(id, index),
        aad: _chunkAad(id, index, last: last),
      );
      out(box.cipherText);
      out(box.mac.bytes);
      index++;
      sent += chunk.length;
    }

    await for (final part in plain) {
      buffer.add(part);
      while (buffer.length > chunkSize ||
          (buffer.length == chunkSize && sent + chunkSize < plainLength)) {
        final all = buffer.takeBytes();
        await flush(Uint8List.sublistView(all, 0, chunkSize), last: false);
        buffer.add(Uint8List.sublistView(all, chunkSize));
      }
    }
    final rest = buffer.takeBytes();
    if (sent + rest.length != plainLength) {
      throw const VaultCorrupt('the source delivered a different length');
    }
    if (rest.isNotEmpty) await flush(rest, last: true);
  }

  /// [seal] for bytes in memory.
  Future<Uint8List> sealBytes(Uint8List plain) async {
    final out = BytesBuilder(copy: false);
    await seal(Stream.value(plain), plain.length, out.add);
    return out.takeBytes();
  }

  /// Opens an encrypted file for reading. Throws [VaultCorrupt] when the key
  /// is wrong or the file is not a vault file.
  Future<VaultReader> open(VaultSource source) async {
    final head = await source.read(0, headerSize);
    if (head.length < headerSize) throw const VaultCorrupt('too short');
    for (var i = 0; i < magic.length; i++) {
      if (head[i] != magic[i]) throw const VaultCorrupt('not a vault file');
    }
    if (head[4] != version) throw const VaultCorrupt('unknown version');
    final d = ByteData.sublistView(head);
    final id = Uint8List.sublistView(head, 8, 24);
    final plainLength = d.getUint64(24);
    final chunk = d.getUint32(32);
    if (chunk != chunkSize) throw const VaultCorrupt('unknown chunk size');
    final keyNonce = Uint8List.sublistView(head, 36, 48);
    final wrapped = Uint8List.sublistView(head, 48, 96);
    final Uint8List fileKey;
    try {
      fileKey = Uint8List.fromList(
        await _aes.decrypt(
          SecretBox(
            wrapped.sublist(0, 32),
            nonce: keyNonce,
            mac: Mac(wrapped.sublist(32)),
          ),
          secretKey: _master,
          aad: _keyAad(id, plainLength, chunk),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const VaultCorrupt('wrong key or damaged header');
    }
    if (await source.length() != sealedLength(plainLength)) {
      throw const VaultCorrupt('cut short or extended');
    }
    return VaultReader._(source, id, SecretKey(fileKey), plainLength);
  }

  /// Decrypts a whole file in memory.
  Future<Uint8List> unsealBytes(Uint8List sealed) async {
    final r = await open(MemoryVaultSource(sealed));
    return await r.read(0, r.plainLength);
  }
}

/// Reads decrypted ranges of one vault file.
final class VaultReader {
  VaultReader._(this._source, this._id, this._key, this.plainLength);

  final VaultSource _source;
  final Uint8List _id;
  final SecretKey _key;
  final int plainLength;
  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap();

  int get _chunks =>
      (plainLength + VaultCrypto.chunkSize - 1) ~/ VaultCrypto.chunkSize;

  Future<Uint8List> _chunk(int index) async {
    final hit = _cache.remove(index);
    if (hit != null) {
      _cache[index] = hit;
      return hit;
    }
    final isLast = index == _chunks - 1;
    final plainSize = isLast
        ? plainLength - index * VaultCrypto.chunkSize
        : VaultCrypto.chunkSize;
    final at =
        VaultCrypto.headerSize +
        index * (VaultCrypto.chunkSize + VaultCrypto.tagSize);
    final raw = await _source.read(at, plainSize + VaultCrypto.tagSize);
    if (raw.length != plainSize + VaultCrypto.tagSize) {
      throw const VaultCorrupt('cut short');
    }
    final Uint8List plain;
    try {
      plain = Uint8List.fromList(
        await VaultCrypto._aes.decrypt(
          SecretBox(
            raw.sublist(0, plainSize),
            nonce: VaultCrypto._nonce(_id, index),
            mac: Mac(raw.sublist(plainSize)),
          ),
          secretKey: _key,
          aad: VaultCrypto._chunkAad(_id, index, last: isLast),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw VaultCorrupt('chunk $index does not match');
    }
    _cache[index] = plain;
    while (_cache.length > 8) {
      _cache.remove(_cache.keys.first);
    }
    return plain;
  }

  /// [length] bytes from [offset], fewer at the end of the file.
  Future<Uint8List> read(int offset, int length) async {
    if (offset >= plainLength || length <= 0) return Uint8List(0);
    final end = min(plainLength, offset + length);
    final first = offset ~/ VaultCrypto.chunkSize;
    final last = (end - 1) ~/ VaultCrypto.chunkSize;
    final out = BytesBuilder(copy: false);
    for (var i = first; i <= last; i++) {
      final c = await _chunk(i);
      final from = i == first ? offset - i * VaultCrypto.chunkSize : 0;
      final to = i == last ? end - i * VaultCrypto.chunkSize : c.length;
      out.add(Uint8List.sublistView(c, from, to));
    }
    return out.takeBytes();
  }
}
