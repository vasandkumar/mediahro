/// ffigen bindings for Mediahro's native libraries and the `VirtualFile`
/// abstraction shared by the engine, the scanner and the image pipeline.
///
/// Bindings live under `lib/src/<library>/` and are generated from the
/// headers in the pinned `mediahro-deps` release (`ffigen/<library>.yaml`).
library;

export 'src/archive/archive_reader.dart'
    show
        ArchiveLimits,
        ArchiveSource,
        ArchiveSyncFileSystem,
        LocalArchiveSource,
        SyncArchiveSource,
        archiveFileSystem,
        normaliseEntryPath;
export 'src/avif/avif_codec.dart';
export 'src/bergamot/bergamot_translator.dart';
export 'src/chromaprint/fingerprinter.dart';
export 'src/cld3/language_identifier.dart';
export 'src/curl/curl_client.dart'
    show
        CurlOptions,
        CurlProtocol,
        CurlSyncFileSystem,
        curlFileSystem,
        sha256ForTesting;
export 'src/curl/list_parser.dart';
export 'src/ebur128/loudness_meter.dart';
// libssh2 + WinCNG, driven by lane C4's Windows SftpFacade (ADR-017).
export 'src/jxl/jxl_codec.dart';
export 'src/libssh2/libssh2_bindings.dart';
export 'src/native/native_library.dart'
    show NativeLibraries, NativeLibrary, NativeLibraryUnavailable;
export 'src/native/posix.dart';
export 'src/nfs/nfs_client.dart'
    show
        NfsOptions,
        NfsSyncFileSystem,
        nfsErrnoError,
        nfsExports,
        nfsFileSystem,
        nfsFindLocalServers;
export 'src/raw/raw_codec.dart';
export 'src/smb2/smb2_client.dart';
export 'src/tesseract/tesseract_ocr.dart';
export 'src/text/text_worker.dart';
export 'src/uchardet/charset_detector.dart';
export 'src/vfs/fd_io.dart';
export 'src/vfs/isolate_file_system.dart';
export 'src/vfs/local_file_system.dart';
export 'src/vfs/virtual_file.dart';
export 'src/vips/vips_codec.dart';
