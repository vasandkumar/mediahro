import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Where the visualiser tap's PCM lives (AUD-046), kept off flash where the
/// OS makes that cheap:
/// - Android and Linux: an anonymous RAM-backed file (`memfd`), which mpv
///   and the reader open as `/proc/self/fd/<n>`.
/// - Windows: a temporary file with `FILE_ATTRIBUTE_TEMPORARY`, which the
///   cache manager keeps in memory instead of writing it out.
/// - Apple: a plain temporary file (apps have no RAM-backed path that mpv's
///   `fopen` can use).
final class TapStorage {
  TapStorage._(this.pcmPath, this.slicePath, this._fds, this._dir);

  /// The PCM mpv appends to (`ao-pcm-file`) and the tap reads windows from.
  final String pcmPath;

  /// The current network slice (`dump-cache` output), overwritten per slice.
  final String slicePath;
  final List<int> _fds;
  final Directory? _dir;

  /// Whether the PCM is RAM-backed (memfd) rather than a file on disk.
  bool get inMemory => _fds.isNotEmpty;

  static Future<TapStorage> create() async {
    if (Platform.isAndroid || Platform.isLinux) {
      final pcm = _memfd('mediahro-tap');
      final slice = pcm < 0 ? -1 : _memfd('mediahro-tap-slice');
      if (slice >= 0) {
        return TapStorage._(_fdPath(pcm), _fdPath(slice), [pcm, slice], null);
      }
      if (pcm >= 0) _close(pcm);
    }
    final dir = await Directory.systemTemp.createTemp('mediahro-tap');
    String file(String name) {
      final f = File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const []);
      if (Platform.isWindows) _markTemporary(f.path);
      return f.path;
    }

    return TapStorage._(file('tap.pcm'), file('slice.mkv'), const [], dir);
  }

  static String _fdPath(int fd) => '/proc/self/fd/$fd';

  /// Bytes of PCM written so far.
  int get pcmLength => _length(pcmPath);

  /// Bytes of the current slice.
  int get sliceLength => _length(slicePath);

  static int _length(String path) {
    final f = File(path);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  Future<void> dispose() async {
    _fds.forEach(_close);
    final dir = _dir;
    if (dir != null) {
      await dir.delete(recursive: true).catchError((Object _) => dir);
    }
  }
}

// memfd_create through syscall(2): bionic only wraps it from API 30, and the
// engine supports API 29.
int _memfd(String name) {
  final nr = switch (Abi.current()) {
    Abi.androidArm64 || Abi.linuxArm64 => 279,
    Abi.androidX64 || Abi.linuxX64 => 319,
    Abi.androidArm || Abi.linuxArm => 385,
    Abi.androidIA32 || Abi.linuxIA32 => 356,
    _ => -1,
  };
  if (nr < 0) return -1;
  try {
    final syscall = DynamicLibrary.process()
        .lookupFunction<
          Long Function(Long, Pointer<Utf8>, UnsignedInt),
          int Function(int, Pointer<Utf8>, int)
        >('syscall');
    // MFD_CLOEXEC.
    return using(
      (arena) => syscall(nr, name.toNativeUtf8(allocator: arena), 1),
    );
  } on Object {
    return -1;
  }
}

void _close(int fd) {
  try {
    DynamicLibrary.process()
        .lookupFunction<Int32 Function(Int32), int Function(int)>('close')(fd);
  } on Object {
    // The descriptor goes with the process anyway.
  }
}

// FILE_ATTRIBUTE_TEMPORARY: keep the file in the cache, avoid writing it out.
void _markTemporary(String path) {
  try {
    final set = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, int)
        >('SetFileAttributesW');
    using((arena) => set(path.toNativeUtf16(allocator: arena), 0x100));
  } on Object {
    // A plain temporary file then.
  }
}
