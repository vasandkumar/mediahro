import 'dart:typed_data';

/// Thrown for malformed or hostile metadata (PRIV-005). Readers stop at the
/// broken block and keep what they parsed before it.
final class MetadataFormatException implements Exception {
  const MetadataFormatException(this.message);

  final String message;

  @override
  String toString() => 'MetadataFormatException: $message';
}

/// Bounds-checked big/little-endian reads over an immutable buffer.
final class ByteView {
  ByteView(this.bytes, {this.bigEndian = true})
    : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  bool bigEndian;
  final ByteData _data;

  int get length => bytes.length;

  Endian get _e => bigEndian ? Endian.big : Endian.little;

  void _check(int offset, int n) {
    if (offset < 0 || n < 0 || offset + n > bytes.length) {
      throw MetadataFormatException('read $n bytes at $offset out of range');
    }
  }

  int u8(int o) {
    _check(o, 1);
    return bytes[o];
  }

  int u16(int o) {
    _check(o, 2);
    return _data.getUint16(o, _e);
  }

  int i16(int o) {
    _check(o, 2);
    return _data.getInt16(o, _e);
  }

  int u32(int o) {
    _check(o, 4);
    return _data.getUint32(o, _e);
  }

  int i32(int o) {
    _check(o, 4);
    return _data.getInt32(o, _e);
  }

  int u64(int o) {
    _check(o, 8);
    return _data.getUint64(o, _e);
  }

  double f32(int o) {
    _check(o, 4);
    return _data.getFloat32(o, _e);
  }

  double f64(int o) {
    _check(o, 8);
    return _data.getFloat64(o, _e);
  }

  Uint8List slice(int o, int n) {
    _check(o, n);
    return Uint8List.sublistView(bytes, o, o + n);
  }

  /// Four ASCII characters (box types, chunk ids).
  String fourCC(int o) => String.fromCharCodes(slice(o, 4));

  bool startsWith(List<int> prefix, [int at = 0]) {
    if (at + prefix.length > bytes.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[at + i] != prefix[i]) return false;
    }
    return true;
  }
}

/// Growable byte sink with endian-aware writes.
final class ByteSink {
  ByteSink({this.bigEndian = true});

  final bool bigEndian;
  final BytesBuilder _b = BytesBuilder(copy: false);
  int get length => _b.length;

  void bytes(List<int> v) => _b.add(v);
  void u8(int v) => _b.addByte(v & 0xff);

  void u16(int v) {
    final d = ByteData(2)..setUint16(0, v, bigEndian ? Endian.big : Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void u32(int v) {
    final d = ByteData(4)..setUint32(0, v, bigEndian ? Endian.big : Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void u64(int v) {
    final d = ByteData(8)..setUint64(0, v, bigEndian ? Endian.big : Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void ascii(String s) => _b.add(s.codeUnits);

  Uint8List take() => _b.takeBytes();
}

/// Writes [v] into [out] at [o] (patching offsets after layout).
void putU32(Uint8List out, int o, int v, {bool bigEndian = true}) {
  ByteData.sublistView(
    out,
  ).setUint32(o, v, bigEndian ? Endian.big : Endian.little);
}

void putU16(Uint8List out, int o, int v, {bool bigEndian = true}) {
  ByteData.sublistView(
    out,
  ).setUint16(o, v, bigEndian ? Endian.big : Endian.little);
}

int indexOfBytes(Uint8List hay, List<int> needle, [int from = 0, int? end]) {
  final stop = (end ?? hay.length) - needle.length;
  outer:
  for (var i = from; i <= stop; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
