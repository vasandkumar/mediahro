// The fake overrides ffigen names (C identifiers).
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;

import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_ffi/src/nfs/nfs_bindings.dart';
import 'package:test/test.dart';

void main() {
  final e = PosixErrno.current;

  test('NET-002 NFS3ERR_* statuses map to the matching VirtualFileError', () {
    // libnfs's nfsstat3_to_errno: status → -errno.
    final cases = {
      -e.noent: VirtualFileError.notFound, // NFS3ERR_NOENT
      -e.acces: VirtualFileError.permissionDenied, // NFS3ERR_ACCES
      -e.perm: VirtualFileError.permissionDenied, // NFS3ERR_PERM
      -e.rofs: VirtualFileError.permissionDenied, // NFS3ERR_ROFS
      -e.notdir: VirtualFileError.notADirectory, // NFS3ERR_NOTDIR
      -e.isdir: VirtualFileError.isADirectory, // NFS3ERR_ISDIR
      -e.exist: VirtualFileError.alreadyExists, // NFS3ERR_EXIST
      -e.notempty: VirtualFileError.alreadyExists, // NFS3ERR_NOTEMPTY
      -e.nospc: VirtualFileError.noSpace, // NFS3ERR_NOSPC
      -e.stale: VirtualFileError.unreachable, // NFS3ERR_STALE
      -e.io: VirtualFileError.io, // NFS3ERR_IO, SERVERFAULT...
    };
    for (final MapEntry(key: rc, value: want) in cases.entries) {
      expect(nfsErrnoError(rc), want, reason: 'rc $rc');
    }
    expect(nfsErrnoError(-e.io, connect: true), VirtualFileError.unreachable);
  });

  test('NET-002 a stale handle is retried once, then reported unreachable', () {
    final b = _FakeNfs()..stat = [-e.stale, 0];
    final fs = NfsSyncFileSystem(
      const NfsOptions(server: 'nas', export: '/media'),
      bindings: b,
    );
    addTearDown(fs.dispose);
    expect(fs.stat('a.mkv').name, 'a.mkv');
    expect(b.statCalls, 2);

    b.stat = [-e.stale, -e.stale];
    expect(
      () => fs.stat('a.mkv'),
      throwsA(
        isA<VirtualFileException>().having(
          (x) => x.error,
          'error',
          VirtualFileError.unreachable,
        ),
      ),
    );
    expect(b.statCalls, 4, reason: 'one retry, no more');
  });
}

/// The libnfs calls a mount and a stat make; everything else throws.
final class _FakeNfs implements NfsBindings {
  List<int> stat = const [];
  int statCalls = 0;

  @override
  ffi.Pointer<nfs_context> nfs_init_context() => ffi.Pointer.fromAddress(8);

  @override
  void nfs_set_timeout(ffi.Pointer<nfs_context> nfs, int milliseconds) {}

  @override
  int nfs_set_version(ffi.Pointer<nfs_context> nfs, int version) => 0;

  @override
  int nfs_mount(
    ffi.Pointer<nfs_context> nfs,
    ffi.Pointer<ffi.Char> server,
    ffi.Pointer<ffi.Char> exportname,
  ) => 0;

  @override
  int nfs_get_readmax(ffi.Pointer<nfs_context> nfs) => 1 << 20;

  @override
  int nfs_get_writemax(ffi.Pointer<nfs_context> nfs) => 1 << 20;

  @override
  int nfs_stat64(
    ffi.Pointer<nfs_context> nfs,
    ffi.Pointer<ffi.Char> path,
    ffi.Pointer<nfs_stat_64> st,
  ) {
    final rc = stat[statCalls++ % stat.length];
    if (rc == 0) {
      st.ref
        ..nfs_mode =
            0x8000 // S_IFREG
        ..nfs_size = 1
        ..nfs_mtime = 0;
    }
    return rc;
  }

  @override
  ffi.Pointer<ffi.Char> nfs_get_error(ffi.Pointer<nfs_context> nfs) =>
      ffi.nullptr;

  @override
  int nfs_umount(ffi.Pointer<nfs_context> nfs) => 0;

  @override
  void nfs_destroy_context(ffi.Pointer<nfs_context> nfs) {}

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
