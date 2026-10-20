import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// CPU time this process has used (user + kernel), for cost measurements.
Duration processCpuTime() {
  if (Platform.isWindows) return _windows();
  if (Platform.isAndroid || Platform.isLinux) return _procStat();
  return _rusage();
}

Duration _windows() {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final current = kernel32.lookupFunction<IntPtr Function(), int Function()>(
    'GetCurrentProcess',
  );
  final times = kernel32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        ),
        int Function(
          int,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )
      >('GetProcessTimes');
  return using((arena) {
    final created = arena<Uint64>();
    final exited = arena<Uint64>();
    final kernel = arena<Uint64>();
    final user = arena<Uint64>();
    if (times(current(), created, exited, kernel, user) == 0) {
      return Duration.zero;
    }
    // FILETIME units of 100 ns.
    return Duration(microseconds: (kernel.value + user.value) ~/ 10);
  });
}

Duration _procStat() {
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  // Fields 14 and 15 (utime, stime) in clock ticks of 1/100 s.
  final ticks = int.parse(fields[11]) + int.parse(fields[12]);
  return Duration(milliseconds: ticks * 10);
}

Duration _rusage() {
  final getrusage = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Int32, Pointer<Int64>),
        int Function(int, Pointer<Int64>)
      >('getrusage');
  return using((arena) {
    // struct rusage starts with ru_utime and ru_stime (timeval: 2 x 64 bit).
    final r = arena<Int64>(18);
    if (getrusage(0, r) != 0) return Duration.zero;
    final micros = r[0] * 1000000 + r[1] + r[2] * 1000000 + r[3];
    return Duration(microseconds: micros);
  });
}
