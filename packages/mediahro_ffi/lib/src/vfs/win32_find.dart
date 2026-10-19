import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// One directory entry from `FindFirstFileExW` with size and mtime, so a
/// Windows listing needs no per-file `stat` (LIB-003 scan budget: a stat
/// costs ~130 µs on NTFS with Defender, the whole listing ~10 µs/entry).
final class Win32DirEntry {
  const Win32DirEntry(
    this.name, {
    required this.isDirectory,
    required this.isReparsePoint,
    required this.size,
    required this.modifiedMs,
  });

  final String name;
  final bool isDirectory;

  /// Symlink or junction; never followed by the scanner.
  final bool isReparsePoint;
  final int size;
  final int modifiedMs;
}

// kernel32 is an OS API, not a bundled C library, so this small binding is
// written by hand (no ffigen header input exists on non-Windows CI).
typedef _FindFirstNative = IntPtr Function(
  Pointer<Utf16> name,
  Int32 infoLevel,
  Pointer<Uint8> data,
  Int32 searchOp,
  Pointer<Void> filter,
  Uint32 flags,
);
typedef _FindFirst = int Function(
  Pointer<Utf16> name,
  int infoLevel,
  Pointer<Uint8> data,
  int searchOp,
  Pointer<Void> filter,
  int flags,
);
typedef _FindNextNative = Int32 Function(IntPtr handle, Pointer<Uint8> data);
typedef _FindNext = int Function(int handle, Pointer<Uint8> data);
typedef _FindCloseNative = Int32 Function(IntPtr handle);
typedef _FindClose = int Function(int handle);

const int _findDataSize = 592;
const int _attrDirectory = 0x10;
const int _attrReparse = 0x400;
const int _findExInfoBasic = 1;
const int _largeFetch = 2;
const int _epochDeltaMs = 11644473600000;

final class _Kernel32 {
  _Kernel32(DynamicLibrary k)
    : findFirst = k.lookupFunction<_FindFirstNative, _FindFirst>(
        'FindFirstFileExW',
      ),
      findNext = k.lookupFunction<_FindNextNative, _FindNext>('FindNextFileW'),
      findClose = k.lookupFunction<_FindCloseNative, _FindClose>('FindClose');

  final _FindFirst findFirst;
  final _FindNext findNext;
  final _FindClose findClose;
}

_Kernel32? _k32;

/// Lists [directoryPath] (a Windows path) or returns null when the call
/// fails, so the caller can fall back to `dart:io` for a precise error.
List<Win32DirEntry>? win32ListDirectory(String directoryPath) {
  if (!Platform.isWindows) return null;
  final k = _k32 ??= _Kernel32(DynamicLibrary.open('kernel32.dll'));
  var dir = directoryPath.replaceAll('/', r'\');
  if (!dir.endsWith(r'\')) dir = '$dir\\';
  // Extended-length prefix lifts the 260-character limit.
  final pattern = dir.startsWith(r'\\?\')
      ? '$dir*'
      : dir.startsWith(r'\\')
      ? '\\\\?\\UNC\\${dir.substring(2)}*'
      : '\\\\?\\$dir*';
  return using((arena) {
    final name = pattern.toNativeUtf16(allocator: arena);
    final data = arena<Uint8>(_findDataSize);
    final handle = k.findFirst(
      name,
      _findExInfoBasic,
      data,
      0,
      nullptr,
      _largeFetch,
    );
    if (handle == -1) return null;
    final out = <Win32DirEntry>[];
    try {
      do {
        final e = _decode(data);
        if (e.name != '.' && e.name != '..') out.add(e);
      } while (k.findNext(handle, data) != 0);
    } finally {
      k.findClose(handle);
    }
    return out;
  });
}

Win32DirEntry _decode(Pointer<Uint8> data) {
  final bd = ByteData.sublistView(data.asTypedList(_findDataSize));
  final attrs = bd.getUint32(0, Endian.little);
  final writeTime = bd.getUint64(20, Endian.little);
  final sizeHigh = bd.getUint32(28, Endian.little);
  final sizeLow = bd.getUint32(32, Endian.little);
  final name = (data + 44).cast<Utf16>().toDartString();
  return Win32DirEntry(
    name,
    isDirectory: attrs & _attrDirectory != 0,
    isReparsePoint: attrs & _attrReparse != 0,
    size: (sizeHigh << 32) | sizeLow,
    modifiedMs: writeTime ~/ 10000 - _epochDeltaMs,
  );
}
