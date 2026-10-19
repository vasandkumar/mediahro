import 'dart:typed_data';

import 'package:mediahro/core/index/xxh3.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Bytes hashed from each end of a file (docs/05 §6).
const int contentHashWindow = 1 << 20;

/// Move-detection hash: xxh3-64 over the first MiB, the last MiB (without
/// overlap) and the little-endian 64-bit size. Reads at most 2 MiB, so it
/// is cheap on network sources.
Future<String> contentHash(VirtualFile file, {int? knownSize}) async {
  final size = knownSize ?? await file.length() ?? 0;
  final head = await file.read(
    0,
    size < contentHashWindow ? size : contentHashWindow,
  );
  var tail = Uint8List(0);
  if (size > contentHashWindow) {
    final tailLen = size - contentHashWindow < contentHashWindow
        ? size - contentHashWindow
        : contentHashWindow;
    tail = await file.read(size - tailLen, tailLen);
  }
  return contentHashOf(head, tail, size);
}

/// [contentHash] over bytes already in memory.
String contentHashOf(Uint8List head, Uint8List tail, int size) {
  final buf = Uint8List(head.length + tail.length + 8)
    ..setRange(0, head.length, head)
    ..setRange(head.length, head.length + tail.length, tail);
  ByteData.sublistView(buf).setUint64(buf.length - 8, size, Endian.little);
  return xxh3Hex(buf);
}
