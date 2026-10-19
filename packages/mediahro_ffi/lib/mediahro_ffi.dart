/// ffigen bindings for Mediahro's native libraries and the `VirtualFile`
/// abstraction shared by the engine, the scanner and the image pipeline.
///
/// Bindings live under `lib/src/<library>/` and are generated from the
/// headers in the pinned `mediahro-deps` release (`ffigen/<library>.yaml`).
library;

export 'src/native/native_library.dart'
    show NativeLibraries, NativeLibrary, NativeLibraryUnavailable;
export 'src/native/posix.dart';
export 'src/nfs/nfs_client.dart'
    show
        NfsOptions,
        NfsSyncFileSystem,
        nfsExports,
        nfsFileSystem,
        nfsFindLocalServers;
export 'src/smb2/smb2_client.dart';
export 'src/vfs/isolate_file_system.dart';
export 'src/vfs/local_file_system.dart';
export 'src/vfs/virtual_file.dart';
