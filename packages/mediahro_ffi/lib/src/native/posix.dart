import 'dart:io';

/// `open(2)` flag values as the C libraries see them on each platform
/// (libsmb2 and libnfs take POSIX flags compiled for their target).
final class PosixOpenFlags {
  const PosixOpenFlags({
    required this.create,
    required this.truncate,
    required this.exclusive,
  });

  factory PosixOpenFlags.forOs(String os) => switch (os) {
    'macos' || 'ios' => const PosixOpenFlags(
      create: 0x200,
      truncate: 0x400,
      exclusive: 0x800,
    ),
    // MSVC CRT _O_CREAT/_O_TRUNC/_O_EXCL.
    'windows' => const PosixOpenFlags(
      create: 0x100,
      truncate: 0x200,
      exclusive: 0x400,
    ),
    _ => const PosixOpenFlags(create: 0x40, truncate: 0x200, exclusive: 0x80),
  };

  static final PosixOpenFlags current = PosixOpenFlags.forOs(
    Platform.operatingSystem,
  );

  int get readOnly => 0;
  int get writeOnly => 1;
  int get readWrite => 2;
  final int create;
  final int truncate;
  final int exclusive;
}

/// errno values per platform C runtime (libsmb2/libnfs return `-errno`).
final class PosixErrno {
  const PosixErrno({
    required this.notempty,
    required this.timedout,
    required this.connrefused,
    required this.hostunreach,
    required this.netunreach,
    required this.stale,
  });

  factory PosixErrno.forOs(String os) => switch (os) {
    'macos' || 'ios' => const PosixErrno(
      notempty: 66,
      timedout: 60,
      connrefused: 61,
      hostunreach: 65,
      netunreach: 51,
      stale: 70,
    ),
    'windows' => const PosixErrno(
      notempty: 41,
      timedout: 138,
      connrefused: 107,
      hostunreach: 110,
      netunreach: 118,
      // MSVC has no ESTALE; libnfs's win32_compat.h defines 116.
      stale: 116,
    ),
    _ => const PosixErrno(
      notempty: 39,
      timedout: 110,
      connrefused: 111,
      hostunreach: 113,
      netunreach: 101,
      stale: 116,
    ),
  };

  static final PosixErrno current = PosixErrno.forOs(Platform.operatingSystem);

  // Identical on every supported C runtime.
  int get perm => 1;
  int get noent => 2;
  int get io => 5;
  int get noexec => 8;
  int get acces => 13;
  int get exist => 17;
  int get notdir => 20;
  int get isdir => 21;
  int get inval => 22;
  int get nospc => 28;
  int get rofs => 30;
  final int notempty;
  final int timedout;
  final int connrefused;
  final int hostunreach;
  final int netunreach;
  final int stale;
}
