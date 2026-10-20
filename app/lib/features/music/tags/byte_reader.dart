import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Thrown by a tag parser on malformed input. Parsers never throw anything
/// else for bad bytes, so the reader can fall back to the file name.
final class TagFormatException implements Exception {
  const TagFormatException(this.message);

  final String message;

  @override
  String toString() => 'TagFormatException($message)';
}

/// A [SparseByteReader] was asked for bytes it does not hold yet; the driver
/// fetches them and runs the parser again.
final class NeedBytes implements Exception {
  const NeedBytes(this.offset, this.length);

  final int offset;
  final int length;

  @override
  String toString() => 'NeedBytes($offset, $length)';
}

/// Synchronous random access over a file's bytes. Tag parsers run on it
/// inside an isolate (CLAUDE.md §1.10).
abstract interface class ByteReader {
  int get length;

  /// Exactly [count] bytes at [offset], or fewer at end of file.
  Uint8List read(int offset, int count);
}

final class MemoryByteReader implements ByteReader {
  MemoryByteReader(this.bytes);

  final Uint8List bytes;

  @override
  int get length => bytes.length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count < 0) throw const TagFormatException('range');
    final start = math.min(offset, bytes.length);
    final end = math.min(offset + count, bytes.length);
    return Uint8List.sublistView(bytes, start, end);
  }
}

/// Reads a local file with positional reads; only the tag regions are read.
final class FileByteReader implements ByteReader {
  FileByteReader(this._file) : length = _file.lengthSync();

  final RandomAccessFile _file;

  @override
  final int length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count < 0) throw const TagFormatException('range');
    if (offset >= length) return Uint8List(0);
    _file.setPositionSync(offset);
    return _file.readSync(math.min(count, length - offset));
  }
}

/// Holds fetched ranges of a remote file. Missing bytes raise [NeedBytes] so
/// the async driver can fetch them without the parser doing I/O.
final class SparseByteReader implements ByteReader {
  SparseByteReader(this.length);

  @override
  final int length;
  final List<(int, Uint8List)> _ranges = [];

  void add(int offset, Uint8List bytes) => _ranges.add((offset, bytes));

  /// Fetched ranges, to rebuild the reader inside an isolate.
  List<(int, Uint8List)> get ranges => List.unmodifiable(_ranges);

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count < 0) throw const TagFormatException('range');
    final end = math.min(offset + count, length);
    if (offset >= end) return Uint8List(0);
    for (final (start, bytes) in _ranges) {
      if (offset >= start && end <= start + bytes.length) {
        return Uint8List.sublistView(bytes, offset - start, end - start);
      }
    }
    throw NeedBytes(offset, end - offset);
  }
}

/// Big- and little-endian helpers over a byte list.
extension ByteFields on Uint8List {
  int u16be(int o) => (this[o] << 8) | this[o + 1];
  int u16le(int o) => this[o] | (this[o + 1] << 8);
  int u24be(int o) => (this[o] << 16) | (this[o + 1] << 8) | this[o + 2];
  int u32be(int o) =>
      (this[o] << 24) | (this[o + 1] << 16) | (this[o + 2] << 8) | this[o + 3];
  int u32le(int o) =>
      this[o] | (this[o + 1] << 8) | (this[o + 2] << 16) | (this[o + 3] << 24);
  int u64be(int o) => (u32be(o) << 32) | u32be(o + 4);
  int u64le(int o) => u32le(o) | (u32le(o + 4) << 32);

  /// ID3v2 sync-safe 28-bit integer.
  int syncSafe(int o) =>
      ((this[o] & 0x7f) << 21) |
      ((this[o + 1] & 0x7f) << 14) |
      ((this[o + 2] & 0x7f) << 7) |
      (this[o + 3] & 0x7f);

  String ascii(int o, int n) =>
      String.fromCharCodes(Uint8List.sublistView(this, o, o + n));

  bool startsWithAscii(String s, [int at = 0]) {
    if (length < at + s.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (this[at + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }
}

/// Parser limits (CLAUDE.md §1.10): a hostile file can't make a parser
/// allocate or loop without bound.
abstract final class TagLimits {
  /// Largest tag block read in one piece (ID3v2, APE, Vorbis comment, ilst).
  static const int maxTagBytes = 32 * 1024 * 1024;

  /// Largest embedded picture kept.
  static const int maxPictureBytes = 16 * 1024 * 1024;

  /// Pictures kept per file.
  static const int maxPictures = 16;

  /// Frames, comments or atoms read per tag.
  static const int maxFields = 4096;

  /// Longest text value kept (lyrics included).
  static const int maxTextBytes = 1024 * 1024;

  /// MP4 atom nesting depth.
  static const int maxDepth = 12;

  /// Chapters kept per file.
  static const int maxChapters = 4096;
}

/// Checked sub-range: throws [TagFormatException] if it leaves [bytes].
Uint8List slice(Uint8List bytes, int offset, int count) {
  if (offset < 0 || count < 0 || offset + count > bytes.length) {
    throw const TagFormatException('truncated');
  }
  return Uint8List.sublistView(bytes, offset, offset + count);
}

/// Reads exactly [count] bytes or throws [TagFormatException].
Uint8List readExact(ByteReader r, int offset, int count) {
  if (count > TagLimits.maxTagBytes) {
    throw const TagFormatException('block too large');
  }
  final b = r.read(offset, count);
  if (b.length != count) throw const TagFormatException('truncated');
  return b;
}
