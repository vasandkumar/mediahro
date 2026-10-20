import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The main display's ICC profile as a file mpv can read (VID-040,
/// `VideoFilterChain.iccAuto`), or null where there is none.
///
/// mpv's `icc-profile-auto` asks the window system, which the libmpv render
/// API does not have, so the engine resolves the profile itself:
/// - Windows: the profile Windows Color Management assigns to the screen
///   (`GetICMProfileW`).
/// - macOS: the display's ColorSync profile (`CGDisplayCopyColorSpace`),
///   written to a temporary file.
/// Android and iOS colour-manage in the system compositor (VID-040 is M W).
String? displayIccProfilePath() {
  try {
    if (Platform.isWindows) return _windows();
    if (Platform.isMacOS) return _macos();
  } on Object {
    // No profile: mpv renders unmanaged, as without iccAuto.
  }
  return null;
}

String? _windows() {
  final user32 = DynamicLibrary.open('user32.dll');
  final gdi32 = DynamicLibrary.open('gdi32.dll');
  final getDc = user32
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
  final releaseDc = user32
      .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
        'ReleaseDC',
      );
  final getProfile = gdi32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>, Pointer<Utf16>),
        int Function(int, Pointer<Uint32>, Pointer<Utf16>)
      >('GetICMProfileW');
  final dc = getDc(0);
  if (dc == 0) return null;
  try {
    return using((arena) {
      const max = 1024;
      final size = arena<Uint32>()..value = max;
      final name = arena<Uint16>(max).cast<Utf16>();
      if (getProfile(dc, size, name) == 0) return null;
      final path = name.toDartString();
      return path.isNotEmpty && File(path).existsSync() ? path : null;
    });
  } finally {
    releaseDc(0, dc);
  }
}

String? _macos() {
  final cg = DynamicLibrary.open(
    '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
  );
  final cf = DynamicLibrary.open(
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
  );
  final mainDisplay = cg.lookupFunction<Uint32 Function(), int Function()>(
    'CGMainDisplayID',
  );
  final copySpace = cg
      .lookupFunction<
        Pointer<Void> Function(Uint32),
        Pointer<Void> Function(int)
      >('CGDisplayCopyColorSpace');
  final copyIcc = cg
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('CGColorSpaceCopyICCData');
  final length = cf
      .lookupFunction<
        IntPtr Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('CFDataGetLength');
  final bytes = cf
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>),
        Pointer<Uint8> Function(Pointer<Void>)
      >('CFDataGetBytePtr');
  final release = cf
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('CFRelease');
  final space = copySpace(mainDisplay());
  if (space == nullptr) return null;
  try {
    final data = copyIcc(space);
    if (data == nullptr) return null;
    try {
      final n = length(data);
      if (n <= 0) return null;
      final icc = Uint8List.fromList(bytes(data).asTypedList(n));
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'mediahro-display.icc',
      )..writeAsBytesSync(icc);
      return file.path;
    } finally {
      release(data);
    }
  } finally {
    release(space);
  }
}
