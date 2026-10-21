import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:mediahro/platform/vault_crypto.dart';

/// A vault file does not match its key: wrong key or PIN, damaged, cut short
/// or changed.
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

/// The vault's file framing (IMG-011, PRIV-007, ADR-008, ADR-039). The AEAD
/// itself is the OS's (`VaultCryptoFacade`); this is only the layout and the
/// associated data that make truncation, reordering and splicing fail:
///
/// ```text
/// "MVL2" | version 2 | fileId[16] | chunkSize u32 | plainLength u64 |
/// keyLength u16 | wrappedKey[keyLength]
/// then per chunk: nonce[12] | cipher[min(chunkSize, left)] | tag[16]
/// ```
///
/// A chunk's associated data is the magic, the file id, the chunk number,
/// whether it is the last, its own length, the length of the whole file and,
/// when given, a 32-byte secret (the PIN-derived token) that never touches
/// the disk and a context (what the file is for). A file without `keyLength` takes its key from the index that
/// lists it.
abstract final class VaultFormat {
  /// Plaintext bytes per chunk: a native call per chunk, so not too small.
  static const int chunkSize = 256 * 1024;

  static const int version = 2;
  static const List<int> magic = [0x4D, 0x56, 0x4C, 0x32];
  static const int fixedHeader = 4 + 1 + 16 + 4 + 8 + 2;
  static const int nonceLength = VaultCryptoFacade.nonceLength;
  static const int tagLength = VaultCryptoFacade.tagLength;

  static int chunkCount(int plainLength) =>
      plainLength == 0 ? 1 : (plainLength + chunkSize - 1) ~/ chunkSize;

  /// Size of the file for [plainLength] bytes and a header key of [keyLength].
  static int sealedLength(int plainLength, {int keyLength = 0}) =>
      fixedHeader +
      keyLength +
      plainLength +
      chunkCount(plainLength) * (nonceLength + tagLength);

  static Uint8List aad({
    required Uint8List fileId,
    required int index,
    required bool last,
    required int chunkLength,
    required int plainLength,
    Uint8List? secret,
    Uint8List? context,
  }) {
    final b = BytesBuilder()
      ..add(magic)
      ..add(fileId)
      ..add((ByteData(4)..setUint32(0, index)).buffer.asUint8List())
      ..addByte(last ? 1 : 0)
      ..add((ByteData(4)..setUint32(0, chunkLength)).buffer.asUint8List())
      ..add((ByteData(8)..setUint64(0, plainLength)).buffer.asUint8List());
    if (secret != null) b.add(secret);
    if (context != null) b.add(context);
    return b.takeBytes();
  }
}

final Random _secure = Random.secure();

/// [n] random bytes from the system generator.
Uint8List randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _secure.nextInt(256)));

/// Writes sealed files.
final class VaultSealer {
  VaultSealer(this.crypto);

  final VaultCryptoFacade crypto;

  /// Seals [plain] ([plainLength] bytes in all, any chunking) under [key]
  /// into [out], header first. [embedKey] puts the wrapped key in the header
  /// (indexes and thumbnails); [secret] binds every chunk to the PIN token.
  /// Returns the file id.
  Future<Uint8List> seal({
    required WrappedKey key,
    required Stream<List<int>> plain,
    required int plainLength,
    required Future<void> Function(Uint8List) out,
    bool embedKey = false,
    Uint8List? secret,
    Uint8List? context,
  }) async {
    final fileId = randomBytes(16);
    final embedded = embedKey ? key.bytes : Uint8List(0);
    final header = BytesBuilder()
      ..add(VaultFormat.magic)
      ..addByte(VaultFormat.version)
      ..add(fileId)
      ..add(
        (ByteData(4)..setUint32(0, VaultFormat.chunkSize)).buffer.asUint8List(),
      )
      ..add((ByteData(8)..setUint64(0, plainLength)).buffer.asUint8List())
      ..add((ByteData(2)..setUint16(0, embedded.length)).buffer.asUint8List())
      ..add(embedded);
    await out(header.takeBytes());

    var index = 0;
    var done = 0;
    final pending = BytesBuilder(copy: false);

    Future<void> emit(Uint8List chunk) async {
      final last = done + chunk.length == plainLength;
      final nonce = randomBytes(VaultFormat.nonceLength);
      final sealed = await crypto.seal(
        key,
        nonce,
        VaultFormat.aad(
          fileId: fileId,
          index: index,
          last: last,
          chunkLength: chunk.length,
          plainLength: plainLength,
          secret: secret,
          context: context,
        ),
        chunk,
      );
      final framed = BytesBuilder(copy: false)
        ..add(nonce)
        ..add(sealed);
      await out(framed.takeBytes());
      done += chunk.length;
      index++;
    }

    if (plainLength == 0) {
      await for (final piece in plain) {
        if (piece.isNotEmpty) throw const VaultCorrupt('too much data');
      }
      await emit(Uint8List(0));
      return fileId;
    }
    var received = 0;
    await for (final piece in plain) {
      received += piece.length;
      if (received > plainLength) throw const VaultCorrupt('too much data');
      pending.add(piece);
      while (pending.length >= VaultFormat.chunkSize) {
        final all = pending.takeBytes();
        await emit(Uint8List.sublistView(all, 0, VaultFormat.chunkSize));
        if (all.length > VaultFormat.chunkSize) {
          pending.add(Uint8List.sublistView(all, VaultFormat.chunkSize));
        }
      }
    }
    if (received != plainLength) throw const VaultCorrupt('too little data');
    if (pending.length > 0) await emit(pending.takeBytes());
    return fileId;
  }
}

/// Reads sealed files, decrypting only the chunks a read touches.
final class VaultReader {
  VaultReader._({
    required this.crypto,
    required this.source,
    required this.key,
    required this.fileId,
    required this.chunkSize,
    required this.plainLength,
    required this.dataStart,
    required this.secret,
    required this.context,
  });

  final VaultCryptoFacade crypto;
  final VaultSource source;
  final WrappedKey key;
  final Uint8List fileId;
  final int chunkSize;
  final int plainLength;
  final int dataStart;
  final Uint8List? secret;

  /// What the file is for (the index of this folder, the picture of this
  /// item): authenticated with every chunk, so a file moved to another place
  /// does not open there.
  final Uint8List? context;

  int _cachedIndex = -1;
  Uint8List? _cached;

  /// Opens [source]. [key] is the file's key from the index; a file that
  /// carries its own key (index, thumbnail) is opened with [master] instead.
  static Future<VaultReader> open({
    required VaultCryptoFacade crypto,
    required VaultSource source,
    WrappedKey? key,
    VaultKeyHandle? master,
    Uint8List? secret,
    Uint8List? context,
  }) async {
    final total = await source.length();
    if (total < VaultFormat.fixedHeader) {
      throw const VaultCorrupt('too short');
    }
    final head = await source.read(0, VaultFormat.fixedHeader);
    if (head.length < VaultFormat.fixedHeader) {
      throw const VaultCorrupt('too short');
    }
    for (var i = 0; i < 4; i++) {
      if (head[i] != VaultFormat.magic[i]) {
        throw const VaultCorrupt('not a vault file');
      }
    }
    if (head[4] != VaultFormat.version) {
      throw const VaultCorrupt('unknown version');
    }
    final view = ByteData.sublistView(head);
    final fileId = Uint8List.fromList(head.sublist(5, 21));
    final chunkSize = view.getUint32(21);
    final plainLength = view.getUint64(25);
    final keyLength = view.getUint16(33);
    if (chunkSize < 4096 || chunkSize > (16 << 20)) {
      throw const VaultCorrupt('bad chunk size');
    }
    if (plainLength > (1 << 40)) throw const VaultCorrupt('bad length');
    final chunks = plainLength == 0
        ? 1
        : (plainLength + chunkSize - 1) ~/ chunkSize;
    final expected =
        VaultFormat.fixedHeader +
        keyLength +
        plainLength +
        chunks * (VaultFormat.nonceLength + VaultFormat.tagLength);
    if (total != expected) throw const VaultCorrupt('wrong size');
    WrappedKey fileKey;
    if (keyLength > 0) {
      if (master == null) throw const VaultCorrupt('no master key');
      final bytes = await source.read(VaultFormat.fixedHeader, keyLength);
      try {
        fileKey = await crypto.adoptFileKey(master, bytes);
      } on VaultCryptoException catch (e) {
        if (e.error == VaultCryptoError.integrityFailure) {
          throw const VaultCorrupt('key does not open');
        }
        rethrow;
      }
    } else {
      if (key == null) throw const VaultCorrupt('no key');
      fileKey = key;
    }
    return VaultReader._(
      crypto: crypto,
      source: source,
      key: fileKey,
      fileId: fileId,
      chunkSize: chunkSize,
      plainLength: plainLength,
      dataStart: VaultFormat.fixedHeader + keyLength,
      secret: secret,
      context: context,
    );
  }

  Future<Uint8List> _chunk(int index) async {
    if (index == _cachedIndex) return _cached!;
    final chunks = plainLength == 0
        ? 1
        : (plainLength + chunkSize - 1) ~/ chunkSize;
    final last = index == chunks - 1;
    final plainLen = last ? plainLength - index * chunkSize : chunkSize;
    final stride = chunkSize + VaultFormat.nonceLength + VaultFormat.tagLength;
    final at = dataStart + index * stride;
    final raw = await source.read(
      at,
      VaultFormat.nonceLength + plainLen + VaultFormat.tagLength,
    );
    if (raw.length !=
        VaultFormat.nonceLength + plainLen + VaultFormat.tagLength) {
      throw const VaultCorrupt('cut short');
    }
    final Uint8List plain;
    try {
      plain = await crypto.open(
        key,
        Uint8List.sublistView(raw, 0, VaultFormat.nonceLength),
        VaultFormat.aad(
          fileId: fileId,
          index: index,
          last: last,
          chunkLength: plainLen,
          plainLength: plainLength,
          secret: secret,
          context: context,
        ),
        Uint8List.sublistView(raw, VaultFormat.nonceLength),
      );
    } on VaultCryptoException catch (e) {
      if (e.error == VaultCryptoError.integrityFailure) {
        throw const VaultCorrupt('does not authenticate');
      }
      rethrow;
    }
    _cachedIndex = index;
    _cached = plain;
    return plain;
  }

  /// Up to [length] bytes of the plaintext from [offset].
  Future<Uint8List> read(int offset, int length) async {
    if (offset < 0 || length < 0) throw RangeError('negative');
    if (offset >= plainLength || length == 0) return Uint8List(0);
    final end = min(plainLength, offset + length);
    final out = BytesBuilder(copy: false);
    var at = offset;
    while (at < end) {
      final index = at ~/ chunkSize;
      final chunk = await _chunk(index);
      final from = at - index * chunkSize;
      final to = min(chunk.length, end - index * chunkSize);
      out.add(Uint8List.sublistView(chunk, from, to));
      at = index * chunkSize + to;
    }
    return out.takeBytes();
  }

  /// All of the plaintext.
  Future<Uint8List> readAll() => read(0, plainLength);

  /// Drops the decrypted chunk held in memory.
  void forget() {
    _cached = null;
    _cachedIndex = -1;
  }
}
