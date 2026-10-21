import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

/// Where analysis PCM lives (AUD-046 tap, ADR-032 decode), kept off flash
/// where the OS makes that cheap:
/// - Android and Linux: anonymous RAM-backed files (`memfd`), which mpv and
///   the reader open as `/proc/self/fd/<n>`. Where the OS refuses that path
///   (Android 16 answers EACCES), a plain temporary file takes over, with the
///   same hole punching, so a decode still holds only undelivered PCM.
/// - Windows: temporary files with `FILE_ATTRIBUTE_TEMPORARY`, which the
///   cache manager keeps in memory instead of writing them out.
/// - Apple: plain temporary files (apps have no RAM-backed path that mpv's
///   `fopen` can use).
///
/// [release] gives back PCM that has been read (hole punching), so a long
/// decode holds only what is not yet delivered.
final class PcmStorage {
  PcmStorage._(this.pcmPath, this.slicePath, this._fds, this._dir);

  /// The PCM mpv appends to (`ao-pcm-file`) and the reader reads from.
  final String pcmPath;

  /// The current network slice (`dump-cache` output), overwritten per slice;
  /// null unless created with `slice: true`.
  final String? slicePath;
  final List<int> _fds;
  final Directory? _dir;
  _Puncher? _puncher;
  int _released = 0;

  /// Whether the PCM is RAM-backed (memfd) rather than a file on disk.
  bool get inMemory => _fds.isNotEmpty;

  /// Opens an anonymous RAM-backed file (tests: stands in for `memfd`).
  @visibleForTesting
  static ({int fd, String path})? Function(String name)? memfdOpener;

  /// Closes a descriptor from [memfdOpener] (tests).
  @visibleForTesting
  static void Function(int fd)? fdCloser;

  static Future<PcmStorage> create({bool slice = true}) async {
    final opener = memfdOpener;
    if (opener != null || Platform.isAndroid || Platform.isLinux) {
      final fds = <int>[];
      final paths = <String>[];
      for (final name in ['mediahro-pcm', if (slice) 'mediahro-slice']) {
        final made = opener != null ? opener(name) : _openMemfd(name);
        if (made == null) break;
        fds.add(made.fd);
        paths.add(made.path);
      }
      // mpv and the reader open the descriptor by path; some Android
      // versions refuse that even for the app's own memfd.
      if (fds.length == (slice ? 2 : 1) && paths.every(_pathUsable)) {
        return PcmStorage._(paths.first, slice ? paths.last : null, fds, null)
          .._puncher = _FdPuncher(fds.first, ownsFd: false);
      }
      fds.forEach(fdCloser ?? _close);
    }
    final dir = await Directory.systemTemp.createTemp('mediahro-pcm');
    String file(String name) {
      final f = File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const []);
      if (Platform.isWindows) _markTemporary(f.path);
      return f.path;
    }

    final storage = PcmStorage._(
      file('audio.pcm'),
      slice ? file('slice.mkv') : null,
      const [],
      dir,
    );
    storage._puncher = Platform.isWindows
        ? _WindowsPuncher.open(storage.pcmPath)
        : (Platform.isIOS || Platform.isMacOS)
        ? _ApplePuncher.open(storage.pcmPath)
        : (Platform.isAndroid || Platform.isLinux)
        ? _FdPuncher.open(storage.pcmPath)
        : null;
    return storage;
  }

  static ({int fd, String path})? _openMemfd(String name) {
    final fd = _memfd(name);
    return fd < 0 ? null : (fd: fd, path: '/proc/self/fd/$fd');
  }

  // Whether the path opens for appending (what mpv does) and for reading
  // (what the reader does).
  static bool _pathUsable(String path) {
    try {
      File(path).openSync(mode: FileMode.append).closeSync();
      File(path).openSync().closeSync();
      return true;
    } on Object {
      return false;
    }
  }

  /// Bytes of PCM written so far (released bytes included).
  int get pcmLength => _length(pcmPath);

  /// Bytes of the current slice.
  int get sliceLength => slicePath == null ? 0 : _length(slicePath!);

  static int _length(String path) {
    final f = File(path);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  /// Bytes at the start of the PCM that have been given back.
  int get released => _released;

  /// Gives back the storage of PCM before [offset], which has been read.
  /// The file keeps its length; released bytes read as zeros.
  void release(int offset) {
    // Whole MB at a time keeps the calls rare and block-aligned.
    const unit = 1 << 20;
    final upTo = offset - offset % unit;
    final p = _puncher;
    if (p == null || upTo <= _released) return;
    if (p.punch(_released, upTo - _released)) _released = upTo;
  }

  Future<void> dispose() async {
    _puncher?.close();
    _puncher = null;
    _fds.forEach(fdCloser ?? _close);
    final dir = _dir;
    if (dir != null) {
      await dir.delete(recursive: true).catchError((Object _) => dir);
    }
  }
}

abstract interface class _Puncher {
  bool punch(int offset, int length);
  void close();
}

// fallocate(FALLOC_FL_PUNCH_HOLE | FALLOC_FL_KEEP_SIZE) on a memfd, or on a
// descriptor of the temporary file where memfd is not usable.
final class _FdPuncher implements _Puncher {
  _FdPuncher(this._fd, {required this.ownsFd});

  final int _fd;
  final bool ownsFd;

  static _Puncher? open(String path) {
    try {
      final open = DynamicLibrary.process()
          .lookupFunction<
            Int Function(Pointer<Utf8>, Int),
            int Function(Pointer<Utf8>, int)
          >('open');
      // O_RDWR.
      final fd = using((arena) => open(path.toNativeUtf8(allocator: arena), 2));
      return fd < 0 ? null : _FdPuncher(fd, ownsFd: true);
    } on Object {
      return null;
    }
  }

  static final int Function(int, int, int, int)? _fallocate = () {
    try {
      return DynamicLibrary.process().lookupFunction<
        Int Function(Int, Int, Int64, Int64),
        int Function(int, int, int, int)
      >('fallocate64');
    } on Object {
      return null;
    }
  }();

  @override
  bool punch(int offset, int length) =>
      (_fallocate?.call(_fd, 0x3, offset, length) ?? -1) == 0;

  @override
  void close() {
    if (ownsFd) _close(_fd);
  }
}

typedef _Ioctl = int Function(
  int,
  int,
  Pointer<Void>,
  int,
  Pointer<Void>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
);

// FSCTL_SET_ZERO_DATA on a sparse file.
final class _WindowsPuncher implements _Puncher {
  _WindowsPuncher._(this._handle);

  final int _handle;

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _Ioctl _ioctl = _kernel32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Uint32,
          Pointer<Void>,
          Uint32,
          Pointer<Void>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(
          int,
          int,
          Pointer<Void>,
          int,
          Pointer<Void>,
          int,
          Pointer<Uint32>,
          Pointer<Void>,
        )
      >('DeviceIoControl');
  static final int Function(int) _closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  static _Puncher? open(String path) {
    try {
      final create = _kernel32
          .lookupFunction<
            IntPtr Function(
              Pointer<Utf16>,
              Uint32,
              Uint32,
              Pointer<Void>,
              Uint32,
              Uint32,
              IntPtr,
            ),
            int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
          >('CreateFileW');
      final handle = using(
        (arena) => create(
          path.toNativeUtf16(allocator: arena),
          0x40000000, // GENERIC_WRITE
          0x7, // FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
          nullptr,
          3, // OPEN_EXISTING
          0x80, // FILE_ATTRIBUTE_NORMAL
          0,
        ),
      );
      if (handle == -1 || handle == 0) return null;
      final sparse = using((arena) {
        final returned = arena<Uint32>();
        // FSCTL_SET_SPARSE.
        return _ioctl(
          handle,
          0x900C4,
          nullptr,
          0,
          nullptr,
          0,
          returned,
          nullptr,
        );
      });
      if (sparse == 0) {
        _closeHandle(handle);
        return null;
      }
      return _WindowsPuncher._(handle);
    } on Object {
      return null;
    }
  }

  @override
  bool punch(int offset, int length) => using((arena) {
    // FILE_ZERO_DATA_INFORMATION: FileOffset, BeyondFinalZero.
    final range = arena<Int64>(2);
    range[0] = offset;
    range[1] = offset + length;
    final returned = arena<Uint32>();
    // FSCTL_SET_ZERO_DATA.
    return _ioctl(
          _handle,
          0x980C8,
          range.cast(),
          16,
          nullptr,
          0,
          returned,
          nullptr,
        ) !=
        0;
  });

  @override
  void close() => _closeHandle(_handle);
}

// fcntl(F_PUNCHHOLE) on APFS.
final class _ApplePuncher implements _Puncher {
  _ApplePuncher._(this._fd);

  final int _fd;

  static final DynamicLibrary _lib = DynamicLibrary.process();
  static final int Function(int, int, Pointer<Void>) _fcntl = _lib
      .lookupFunction<
        Int Function(Int, Int, VarArgs<(Pointer<Void>,)>),
        int Function(int, int, Pointer<Void>)
      >('fcntl');

  static _Puncher? open(String path) {
    try {
      final open = _lib
          .lookupFunction<
            Int Function(Pointer<Utf8>, Int),
            int Function(Pointer<Utf8>, int)
          >('open');
      // O_RDWR.
      final fd = using((arena) => open(path.toNativeUtf8(allocator: arena), 2));
      return fd < 0 ? null : _ApplePuncher._(fd);
    } on Object {
      return null;
    }
  }

  @override
  bool punch(int offset, int length) => using((arena) {
    // struct fpunchhole { uint32 fp_flags, reserved; off_t offset, length; }
    final args = arena<Int64>(3);
    args[0] = 0;
    args[1] = offset;
    args[2] = length;
    // F_PUNCHHOLE.
    return _fcntl(_fd, 99, args.cast()) == 0;
  });

  @override
  void close() => _close(_fd);
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
