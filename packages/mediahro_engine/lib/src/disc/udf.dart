/// Read-only UDF reader for disc images (VID-001 ISO, VID-007): DVD-Video
/// (UDF 1.02 bridge) and Blu-ray (UDF 2.50/2.60 with metadata partitions).
/// Files are exposed as [VirtualFile]s over the image, so titles stream
/// from an `.iso` on any source without extraction.
///
/// Own implementation of ECMA-167 / OSTA UDF structures; no GPL code
/// (libdvdread's UDF code is GPL). Bounded: directory sizes and entry
/// counts are capped (docs/13 parser limits).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro_ffi/mediahro_ffi.dart';

const int _sector = 2048;
const int _maxDirectoryBytes = 4 * 1024 * 1024;
const int _maxEntries = 100000;

final class UdfFormatException implements Exception {
  const UdfFormatException(this.message);
  final String message;
  @override
  String toString() => 'UdfFormatException: $message';
}

/// One extent of a file: [length] bytes at logical block [lbn] of
/// partition reference [partition].
final class _Extent {
  const _Extent(this.partition, this.lbn, this.length);
  final int partition;
  final int lbn;
  final int length;
}

/// A file or directory inside a UDF image.
final class UdfEntry {
  UdfEntry._(this._fs, this.name, this.isDirectory, this.size, this._extents);

  final UdfImage _fs;
  final String name;
  final bool isDirectory;
  final int size;
  final List<_Extent> _extents;
  List<UdfEntry>? _children;

  Future<List<UdfEntry>> children() async =>
      _children ??= isDirectory ? await _fs._readDirectory(this) : const [];

  /// Case-insensitive lookup of a direct child.
  Future<UdfEntry?> child(String name) async {
    final n = name.toUpperCase();
    for (final c in await children()) {
      if (c.name.toUpperCase() == n) return c;
    }
    return null;
  }

  /// The file's bytes as a seekable [VirtualFile] over the image.
  VirtualFile open() => _UdfFile(_fs, this);

  @override
  String toString() => 'UdfEntry($name, ${isDirectory ? 'dir' : '$size B'})';
}

/// A mounted UDF image.
final class UdfImage {
  UdfImage._(this._image, this._blockSize, this._partitions);

  final VirtualFile _image;
  final int _blockSize;

  /// Partition reference → mapping.
  final List<_PartitionMap> _partitions;
  late final UdfEntry root;

  /// Whether [image] starts with UDF volume structures.
  static Future<bool> isUdf(VirtualFile image) async {
    try {
      final avdp = await _read(image, 256 * _sector, _sector);
      return _tag(avdp) == 2;
    } on Object {
      return false;
    }
  }

  static Future<Uint8List> _read(VirtualFile f, int offset, int length) async {
    final b = await f.read(offset, length);
    if (b.length < length) {
      throw const UdfFormatException('image truncated');
    }
    return b;
  }

  static int _u16(Uint8List b, int o) => b[o] | b[o + 1] << 8;
  static int _u32(Uint8List b, int o) =>
      b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;
  static int _u64(Uint8List b, int o) => _u32(b, o) + (_u32(b, o + 4) << 32);
  static int _tag(Uint8List b) => _u16(b, 0);

  /// Opens the UDF file system in [image].
  static Future<UdfImage> open(VirtualFile image) async {
    final avdp = await _read(image, 256 * _sector, _sector);
    if (_tag(avdp) != 2) {
      throw const UdfFormatException('no anchor volume descriptor');
    }
    final vdsLength = _u32(avdp, 16);
    final vdsLocation = _u32(avdp, 20);
    final physical = <int, int>{}; // partition number → start sector
    Uint8List? lvd;
    for (var i = 0; i < vdsLength ~/ _sector && i < 64; i++) {
      final d = await _read(image, (vdsLocation + i) * _sector, _sector);
      switch (_tag(d)) {
        case 5: // Partition Descriptor
          physical[_u16(d, 22)] = _u32(d, 188);
        case 6: // Logical Volume Descriptor
          lvd = d;
        case 8: // Terminating Descriptor
          i = 1 << 30;
      }
    }
    if (lvd == null || physical.isEmpty) {
      throw const UdfFormatException('no logical volume');
    }
    final blockSize = _u32(lvd, 212);
    if (blockSize != _sector) {
      throw UdfFormatException('unsupported block size $blockSize');
    }
    final mapCount = _u32(lvd, 268);
    final maps = <_PartitionMap>[];
    var o = 440;
    for (var i = 0; i < mapCount && i < 8; i++) {
      final type = lvd[o];
      final len = lvd[o + 1];
      if (type == 1) {
        maps.add(_PartitionMap.physical(physical[_u16(lvd, o + 4)] ?? 0));
      } else if (type == 2) {
        final id = ascii.decode(
          lvd.sublist(o + 5, o + 28).takeWhile((c) => c != 0).toList(),
          allowInvalid: true,
        );
        final start = physical[_u16(lvd, o + 38)] ?? 0;
        if (id.contains('Metadata')) {
          maps.add(_PartitionMap.metadata(start, _u32(lvd, o + 40)));
        } else {
          // Virtual/sparable partitions map 1:1 on read-only pressed discs.
          maps.add(_PartitionMap.physical(start));
        }
      }
      o += len == 0 ? 6 : len;
    }
    final fs = UdfImage._(image, blockSize, maps);
    for (final m in maps) {
      if (m.metadataFile != null) await fs._loadMetadata(m);
    }
    // File Set Descriptor: long_ad in the LVD's contents use.
    final fsdLbn = _u32(lvd, 252);
    final fsdPart = _u16(lvd, 256);
    final fsd = await fs._block(fsdPart, fsdLbn);
    if (_tag(fsd) != 256) {
      throw const UdfFormatException('no file set descriptor');
    }
    final rootLbn = _u32(fsd, 404);
    final rootPart = _u16(fsd, 408);
    fs.root = await fs._entry('', rootPart, rootLbn, isDirectory: true);
    return fs;
  }

  /// Byte offset in the image of [lbn] in partition [ref].
  Future<int> _offset(int ref, int lbn) async {
    if (ref >= _partitions.length) {
      throw UdfFormatException('partition $ref');
    }
    final m = _partitions[ref];
    if (m.metadataFile == null) return (m.start + lbn) * _sector;
    // Metadata partition: logical blocks live inside the metadata file.
    var pos = lbn * _blockSize;
    for (final e in m.metadataExtents) {
      if (pos < e.length) return (m.start + e.lbn) * _sector + pos;
      pos -= e.length;
    }
    throw UdfFormatException('metadata block $lbn out of range');
  }

  int _dataRef(int ref) {
    final m = _partitions[ref];
    if (m.metadataFile == null) return ref;
    for (var i = 0; i < _partitions.length; i++) {
      if (_partitions[i].metadataFile == null &&
          _partitions[i].start == m.start) {
        return i;
      }
    }
    return ref;
  }

  Future<Uint8List> _block(int ref, int lbn) async =>
      await _read(_image, await _offset(ref, lbn), _sector);

  Future<void> _loadMetadata(_PartitionMap m) async {
    final fe = await _read(
      _image,
      (m.start + m.metadataFile!) * _sector,
      _sector,
    );
    final (_, extents) = _allocation(fe, partitionOfIcb: -1);
    m.metadataExtents = [for (final e in extents) _Extent(-1, e.lbn, e.length)];
  }

  /// Parses a File Entry (261) or Extended File Entry (266):
  /// (information length, extents).
  (int, List<_Extent>) _allocation(
    Uint8List fe, {
    required int partitionOfIcb,
  }) {
    final tag = _tag(fe);
    final int lea;
    final int lad;
    final int adStart;
    if (tag == 261) {
      lea = _u32(fe, 168);
      lad = _u32(fe, 172);
      adStart = 176 + lea;
    } else if (tag == 266) {
      lea = _u32(fe, 208);
      lad = _u32(fe, 212);
      adStart = 216 + lea;
    } else {
      throw UdfFormatException('not a file entry (tag $tag)');
    }
    final size = _u64(fe, 56);
    final adType = _u16(fe, 34) & 0x07;
    final extents = <_Extent>[];
    switch (adType) {
      case 0: // short_ad
        for (
          var o = adStart;
          o + 8 <= adStart + lad && o + 8 <= fe.length;
          o += 8
        ) {
          final len = _u32(fe, o) & 0x3FFFFFFF;
          if (len == 0) break;
          extents.add(_Extent(partitionOfIcb, _u32(fe, o + 4), len));
        }
      case 1: // long_ad
        for (
          var o = adStart;
          o + 16 <= adStart + lad && o + 16 <= fe.length;
          o += 16
        ) {
          final len = _u32(fe, o) & 0x3FFFFFFF;
          if (len == 0) break;
          extents.add(_Extent(_u16(fe, o + 8), _u32(fe, o + 4), len));
        }
      case 3: // embedded data
        return (size, [_Extent(-2, adStart, lad)]);
      default:
        throw UdfFormatException('allocation type $adType');
    }
    return (size, extents);
  }

  final _embedded = Expando<Uint8List>();

  Future<UdfEntry> _entry(
    String name,
    int ref,
    int lbn, {
    required bool isDirectory,
  }) async {
    final fe = await _block(ref, lbn);
    // short_ads in entries kept in a UDF 2.5 metadata partition address the
    // underlying physical partition, where file data lives.
    final (size, extents) = _allocation(fe, partitionOfIcb: _dataRef(ref));
    final entry = UdfEntry._(this, name, isDirectory, size, extents);
    if (extents.length == 1 && extents.first.partition == -2) {
      final e = extents.first;
      _embedded[entry] = Uint8List.sublistView(fe, e.lbn, e.lbn + e.length);
    }
    return entry;
  }

  Future<Uint8List> _content(UdfEntry e, int offset, int length) async {
    final embedded = _embedded[e];
    if (embedded != null) {
      final end = (offset + length).clamp(0, embedded.length);
      return Uint8List.sublistView(embedded, offset.clamp(0, end), end);
    }
    final out = BytesBuilder(copy: false);
    var pos = offset;
    var left = length.clamp(0, e.size - offset < 0 ? 0 : e.size - offset);
    var base = 0;
    for (final x in e._extents) {
      if (left <= 0) break;
      if (pos < base + x.length) {
        final within = pos - base;
        final take = (x.length - within).clamp(0, left);
        // Extents are contiguous runs of blocks in one partition.
        final start = await _offset(x.partition, x.lbn);
        final chunk = await _image.read(start + within, take);
        out.add(chunk);
        pos += chunk.length;
        left -= chunk.length;
        if (chunk.length < take) break;
      }
      base += x.length;
    }
    return out.takeBytes();
  }

  Future<List<UdfEntry>> _readDirectory(UdfEntry dir) async {
    if (dir.size > _maxDirectoryBytes) {
      throw const UdfFormatException('directory too large');
    }
    final b = await _content(dir, 0, dir.size);
    final out = <UdfEntry>[];
    var o = 0;
    while (o + 38 <= b.length && out.length < _maxEntries) {
      if (_tag(Uint8List.sublistView(b, o)) != 257) break;
      final characteristics = b[o + 18];
      final nameLength = b[o + 19];
      final icbLbn = _u32(b, o + 24);
      final icbPart = _u16(b, o + 28);
      final implUse = _u16(b, o + 36);
      final nameStart = o + 38 + implUse;
      final total = (38 + implUse + nameLength + 3) & ~3;
      final isParent = characteristics & 0x08 != 0;
      final isDeleted = characteristics & 0x04 != 0;
      if (!isParent && !isDeleted && nameLength > 0) {
        final name = _dstring(
          Uint8List.sublistView(b, nameStart, nameStart + nameLength),
        );
        out.add(
          await _entry(
            name,
            icbPart,
            icbLbn,
            isDirectory: characteristics & 0x02 != 0,
          ),
        );
      }
      o += total;
    }
    return out;
  }

  /// OSTA compressed Unicode (8-bit or UTF-16BE).
  static String _dstring(Uint8List b) {
    if (b.isEmpty) return '';
    if (b[0] == 16) {
      final units = <int>[
        for (var i = 1; i + 1 < b.length; i += 2) b[i] << 8 | b[i + 1],
      ];
      return String.fromCharCodes(units);
    }
    return latin1.decode(b.sublist(1));
  }
}

final class _PartitionMap {
  _PartitionMap.physical(this.start) : metadataFile = null;
  _PartitionMap.metadata(this.start, int this.metadataFile);

  final int start;
  final int? metadataFile;
  List<_Extent> metadataExtents = const [];
}

final class _UdfFile implements VirtualFile {
  _UdfFile(this._fs, this._entry);
  final UdfImage _fs;
  final UdfEntry _entry;

  @override
  Uri get uri => Uri(scheme: 'udf', path: _entry.name);

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => _entry.size;

  @override
  Future<Uint8List> read(int offset, int length) =>
      _fs._content(_entry, offset, length);

  @override
  Future<void> close() async {}
}
